# Safe NPM (safe-npm)

A system-wide security wrapper for npm and npx designed to protect developers from malicious packages, typosquatting, and compromised transitive dependencies.

## The Problem
Malicious actors frequently upload compromised packages to the NPM registry. Often, these are disguised as popular libraries (typosquatting) or are hidden deep inside the dependency tree of a legitimate package. Usually, these malicious packages are discovered and removed by the NPM security team within a few days. 

However, if you happen to run `npm install` during that short window, your system gets compromised.

## The Solution
`safe-npm` disables the raw `npm` and `npx` commands and replaces them with **`sn` (Safe NPM)** and **`snx` (Safe NPX)**. 

Before installing or executing any package, `safe-npm` intercepts the command, maps out the **entire nested dependency tree**, and checks the publication date of every single package about to be installed. If any package (direct or transitive) is newer than 7 days, the installation pauses, alerts you to the exact suspicious package, and requires manual confirmation to proceed.

### Key Features
- Blocks Native Commands: Prevents accidental use of npm and npx system-wide.
- Deep Tree Scanning: Evaluates the exact versions of all nested dependencies, not just the top-level package.
- Blazing Fast: Uses concurrent background workers to query NPM registry dates in parallel.
- System-Wide: Applies to all user accounts on the machine.
- Sudo-Proof: Because the scripts sit in `/usr/local/bin`, they protect you even if you run `sudo sn install -g`.

---

## Prerequisites
`safe-npm` requires `jq` to quickly parse the JSON dependency tree.
```bash
# On Debian/Ubuntu
sudo apt update && sudo apt install jq -y
```

---

## Installation

Since this setup applies system-wide, you will need `sudo` privileges to copy the files into the correct directories.

**1. Clone the repository and enter the directory**
```bash
git clone https://github.com/YOUR_USERNAME/safe-npm.git
cd safe-npm
```

**2. Make all scripts executable**
```bash
chmod +x sn snx npm npx sn-core.sh
```

**3. Copy the core engine to the system libraries folder**
```bash
sudo cp sn-core.sh /usr/local/lib/
```

**4. Copy the executable commands to the system binaries folder**
```bash
sudo cp npm npx sn snx /usr/local/bin/
```

Installation is complete! The system will now route all users through `safe-npm`.

---

## Usage



Simply replace your normal Node.js workflow commands with `sn` and `snx`. 

```bash
# Instead of npm install react
sn install react

# Instead of npm run build
sn run build

# Instead of npx create-react-app my-app
snx create-react-app my-app
```

If you or another user accidentally types `npm install`, you will see:
```text
[BLOCKED] The raw 'npm' command is disabled for security.
Please use sn (Safe NPM) instead.
```

`safe-npm` is intelligent. It distinguishes between safe local commands and dangerous registry-facing commands.

### Blocked Commands
The following will be blocked when using raw `npm`, forcing you to use `sn`:
- `npm install` / `npm i` / `npm ci`
- `npm add`
- `npm update`
- `npx <remote-package>`

### Allowed Commands
The following will pass through and work normally with raw `npm`:
- `npm run <script>`
- `npm test`
- `npm list`
- `npx <local-package>` (if already installed in node_modules)

### What happens when a threat is detected?
If you try to install a package that includes a recently published dependency, you will see a warning like this:

```text
[Security Check] Simulating install to map ALL nested dependencies...
[Security Check] Checking age of dependencies in parallel...

 WARNING: RECENTLY PUBLISHED DEPENDENCIES DETECTED 
The following packages (including nested dependencies) are less than 7 days old:
  -> express@4.18.3 (Published 2 days ago)
  -> hidden-malicious-dep@1.0.1 (Published 0 days ago)

Malicious packages are often hidden deep in dependency trees.
Are you sure you want to proceed? (y/N): 
```

---

## How It Works Under the Hood

1. **Interception**: `/usr/local/bin/sn` catches your command before the real Node.js binaries see it.
2. **Dry Run Simulation**: It executes `npm install <packages> --dry-run --json`. This forces NPM to resolve the entire dependency tree without actually downloading or executing anything.
3. **JSON Parsing**: It passes the resulting data to `jq` to extract a clean list of every single package and exact version that will be added or updated.
4. **Concurrent API Checks**: It loops through that list, spinning up background processes (`&`) to query the `npm view` API for the exact publication timestamp of each package. 
5. **Evaluation**: It converts ISO 8601 timestamps to UNIX epoch time, compares it to your system's current time, and checks if it falls under the configured threshold.

---

## Configuration

By default, the script flags any package newer than **7 days**. If you want to change this threshold, edit the core engine file:

```bash
sudo nano /usr/local/lib/sn-core.sh
```
Change `NPM_SECURITY_DAYS=7` to your preferred number of days.

---

## NVM Compatibility
`safe-npm` is fully compatible with Node Version Manager (NVM). The engine will automatically detect and use whichever Node version is currently active via NVM.

However, because NVM places its binaries at the very front of your shell's `$PATH`, it will bypass the `npm` and `npx` blocking scripts located in `/usr/local/bin/`. 

To fix this and successfully block the native commands for all users on the system, you must create a global shell function routing in the system-wide bash configuration:

1. Open the global bashrc file:
   ```bash
   sudo nano /etc/bash.bashrc
   ```

2. Paste the following at the very bottom:
   ```bash
   # Force npm and npx commands to use the safe-npm blockers
   npm() { /usr/local/bin/npm "$@"; }
   npx() { /usr/local/bin/npx "$@"; }
   ```

3. Restart your terminal. The native commands are now successfully blocked! 
*(Note: If you use Zsh instead of Bash, add those lines to `/etc/zsh/zshrc` instead).*

## Limitations & Best Practices

- **Zero-Day Attacks**: If a malicious package is published, and you bypass the warning to install it on day 1, this tool cannot save you. It relies on the buffer time it takes for the community/registry to discover and remove malware.
- **Install Scripts**: As a general Node.js security best practice, you should also run `npm config set ignore-scripts true` globally. This prevents packages from running arbitrary shell scripts automatically upon download.

## License
MIT License. Feel free to fork, modify, and distribute to keep the community safe!
