#!/bin/bash
# /usr/local/lib/sn-core.sh (v1.2 - Schema Agnostic)

NPM_SECURITY_DAYS=7
THRESHOLD_SEC=$((NPM_SECURITY_DAYS * 86400))
NOW_SEC=$(date +%s)

REAL_NPM=$(which -a npm | grep -v "/usr/local/bin/npm" | head -n 1)
REAL_NPX=$(which -a npx | grep -v "/usr/local/bin/npx" | head -n 1)

if [ -z "$REAL_NPM" ]; then
    echo -e "\e[31mError: Original system 'npm' not found.\e[0m"
    exit 1
fi

check_packages() {
    echo -e "\e[34m[Security Check]\e[0m Simulating install to map ALL nested dependencies..."

    local raw_out
    # Capture dry-run output
    raw_out=$("$REAL_NPM" install "$@" --dry-run --json 2>/dev/null)

    # Extract only the JSON part (strips the "change vitest..." text from the top)
    local dry_run_out
    dry_run_out=$(echo "$raw_out" | sed -n '/^{/,$p')

    # If the output isn't valid JSON, halt
    if ! echo "$dry_run_out" | jq -e . >/dev/null 2>&1; then
        echo -e "\n\e[31m[Error]\e[0m Could not parse the dependency tree JSON."
        echo -e "\e[33mTip:\e[0m This often happens due to network errors or peer-dependency conflicts."
        read -p "Abort installation for safety? (Y/n): " abort < /dev/tty
        if [[ ! "$abort" =~ ^[Nn]$ ]]; then
            echo -e "\e[31mSecurity check failed. Aborting.\e[0m"
            exit 1
        fi
        return 0
    fi

    # Extract packages using a schema-agnostic JQ filter
    # This covers .added, .updated, .add, and .change (nested)
    local pending_pkgs
    pending_pkgs=$(echo "$dry_run_out" | jq -r '
        (try .added[]? | "\(.name)||\(.version)"),
        (try .updated[]? | "\(.name)||\(.version)"),
        (try .add[]? | "\(.name)||\(.version)"),
        (try .change[]? | "\(.to.name)||\(.to.version)")
    ' 2>/dev/null | grep "||" | sort -u)

    if [ -z "$pending_pkgs" ]; then
        echo -e "\e[32m[Safe]\e[0m No new packages detected for download."
        return 0
    fi

    local pkg_count
    pkg_count=$(echo "$pending_pkgs" | wc -l)
    echo -e "\e[34m[Security Check]\e[0m Checking age of $pkg_count packages..."

    local tmp_warn
    tmp_warn=$(mktemp)

    echo "$pending_pkgs" | while IFS= read -r item; do
        if [ -z "$item" ]; then continue; fi
        (
            local name="${item%||*}"
            local version="${item#*||}"
            local pub_time
            pub_time=$("$REAL_NPM" view "${name}@${version}" "time.[\"${version}\"]" 2>/dev/null)

            if [ -n "$pub_time" ]; then
                pub_time="${pub_time%\"}"
                pub_time="${pub_time#\"}"
                local pub_sec
                pub_sec=$(date -d "$pub_time" +%s 2>/dev/null)

                if [ -n "$pub_sec" ]; then
                    local diff=$((NOW_SEC - pub_sec))
                    if [ "$diff" -lt "$THRESHOLD_SEC" ]; then
                        local days=$((diff / 86400))
                        echo -e "  \e[31m->\e[0m $name@$version \e[90m(Published $days days ago)\e[0m" >> "$tmp_warn"
                    fi
                fi
            fi
        ) &
    done
    wait

    if [ -s "$tmp_warn" ]; then
        echo -e "\n\e[41m\e[97m WARNING: RECENTLY PUBLISHED DEPENDENCIES DETECTED \e[0m"
        echo -e "The following packages are less than $NPM_SECURITY_DAYS days old:"
        cat "$tmp_warn"
        rm -f "$tmp_warn"
        echo -e "\n\e[33mMalicious packages are often removed within 72 hours of publication.\e[0m"
        read -p "Are you sure you want to proceed? (y/N): " confirm < /dev/tty
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "\e[31mAborted by user.\e[0m"
            exit 1
        fi
    else
        echo -e "\e[32m[Safe]\e[0m All dependencies are older than $NPM_SECURITY_DAYS days."
        rm -f "$tmp_warn"
    fi
}
