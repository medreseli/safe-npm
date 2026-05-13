#!/bin/bash
# /usr/local/lib/sn-core.sh

NPM_SECURITY_DAYS=7
THRESHOLD_SEC=$((NPM_SECURITY_DAYS * 86400))
NOW_SEC=$(date +%s)

# Locate the actual Node.js system binaries (ignores our custom wrappers)
REAL_NPM=$(which -a npm | grep -v "/usr/local/bin/npm" | head -n 1)
REAL_NPX=$(which -a npx | grep -v "/usr/local/bin/npx" | head -n 1)

if [ -z "$REAL_NPM" ]; then
    echo -e "\e[31mError: Original system 'npm' not found.\e[0m"
    exit 1
fi

check_packages() {
    echo -e "\e[34m[Security Check]\e[0m Simulating install to map ALL nested dependencies..."

    # Perform a dry run to extract the exact nested dependency tree
    local dry_run_out
    dry_run_out=$("$REAL_NPM" install "$@" --dry-run --json 2>/dev/null)

    # Extract packages that are about to be added or updated
    local pending_pkgs
    pending_pkgs=$(echo "$dry_run_out" | jq -r '.added[]?, .updated[]? | "\(.name)||\(.version)"')

    if [ -z "$pending_pkgs" ]; then
        return 0 # Nothing new is being installed
    fi

    echo -e "\e[34m[Security Check]\e[0m Checking age of dependencies in parallel..."
    local tmp_warn
    tmp_warn=$(mktemp)

    # Loop through dependencies and check their ages concurrently for massive speed
    echo "$pending_pkgs" | while IFS= read -r item; do
        if [ -z "$item" ]; then continue; fi

        (
            local name="${item%||*}"
            local version="${item#*||}"

            # Fetch the exact timestamp this specific version was published
            local pub_time
            pub_time=$("$REAL_NPM" view "${name}@${version}" "time.[\"${version}\"]" 2>/dev/null)

            if [ -n "$pub_time" ]; then
                # Strip potential JSON quotes
                pub_time="${pub_time%\"}"
                pub_time="${pub_time#\"}"

                local pub_sec
                pub_sec=$(date -d "$pub_time" +%s 2>/dev/null)

                if [ -n "$pub_sec" ]; then
                    local diff=$((NOW_SEC - pub_sec))
                    if [ "$diff" -lt "$THRESHOLD_SEC" ]; then
                        local days=$((diff / 86400))
                        # Append warning to temporary file safely
                        echo -e "  \e[31m->\e[0m $name@$version \e[90m(Published $days days ago)\e[0m" >> "$tmp_warn"
                    fi
                fi
            fi
        ) &
    done

    # Wait for all background checks to finish
    wait

    if [ -s "$tmp_warn" ]; then
        echo -e "\n\e[41m\e[97m WARNING: RECENTLY PUBLISHED DEPENDENCIES DETECTED \e[0m"
        echo -e "The following packages (including nested dependencies) are less than $NPM_SECURITY_DAYS days old:"
        cat "$tmp_warn"
        echo -e "\n\e[33mMalicious packages are often hidden deep in dependency trees.\e[0m"

        rm -f "$tmp_warn"

        # Read directly from tty so this works correctly even under sudo
        read -p "Are you sure you want to proceed? (y/N): " confirm < /dev/tty
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "\e[31mAborted by user.\e[0m"
            exit 1
        fi
    else
        echo -e "\e[32m[Safe]\e[0m All nested dependencies are older than $NPM_SECURITY_DAYS days."
        rm -f "$tmp_warn"
    fi
}
