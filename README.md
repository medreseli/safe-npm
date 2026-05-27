# Safe NPM (safe-npm)

A system-wide security wrapper for npm and npx designed to protect developers from malicious packages, typosquatting, and compromised transitive dependencies.

## The Problem
Malicious actors frequently upload compromised packages to the NPM registry. Often, these are disguised as popular libraries (typosquatting) or are hidden deep inside the dependency tree of a legitimate package. Usually, these malicious packages are discovered and removed by the NPM security team within a few days. 

However, if you happen to run `npm install` during that short window, your system gets compromised.

## The Solution
`safe-npm` disables the raw `npm` and `npx` commands and replaces them with **`sn` (Safe NPM)** and **`snx` (Safe NPX)**. 

Before installing or executing any package, `safe-npm` intercepts the command, maps out the **entire nested dependency tree**, and checks the publication date of every single package about to be installed. If any package (direct or transitive) is newer than 7 days, the installation pauses, alerts you to the exact suspicious package, and requires manual confirmation to proceed.

### Key Features
- **Blocks Native Commands**: Prevents accidental use of npm and npx system-wide.
- **Deep Tree Scanning**: Evaluates the exact versions of all nested dependencies, not just the top-level package.
- **Interactive Prompts**: When blocked via raw `npm` or `npx`, it offers an automated prompt to execute the safe command instantly without retyping.
- **Controlled Concurrency**: Implements a parallel worker pool (limited to 15 concurrent jobs) to prevent CPU spikes or registry rate-limiting (HTTP 429) on large projects.
- **Smart Caching**: Once a package version is verified, its publication date is stored locally. Subsequent checks are near-instant.
- **System-Wide**: Applies to all user accounts on the machine.
- **Sudo-Proof**: Because the scripts sit in `/usr/local/bin`, they protect you even if you run `sudo sn install -g`.

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
git clone https://github.com/medreseli/safe-npm.git
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

### Interactive Command Redirection
If you or another user accidentally types `npm install`, you will see:
```text
[BLOCKED] Installation commands are disabled via raw 'npm' for security.
Would you like to run 'sn install' instead? (Y/n): 
```
Simply press **Enter** or **Y**, and `safe-npm` will automatically execute the safe process for you.

### Intelligent Routing
`safe-npm` distinguishes between safe local commands and dangerous registry-facing commands.

#### Blocked Commands
The following will be blocked when using raw `npm`, prompting you to run with `sn`:
- `npm install` / `npm i` / `npm ci`
- `npm add`
- `npm update` / `npm up` / `npm upgrade`
- `npx <remote-package>`

#### Allowed Commands
The following bypass the safety checks and will pass through directly to native binaries:
- `npm run <script>`
- `npm test`
- `npm list`
- `npm link` (inherently safe local symlinking for local development)
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

Malicious packages are often removed within 72 hours of publication.
Are you sure you want to proceed? (y/N): 
```

---

## How It Works Under the Hood

1. **Interception**: `/usr/local/bin/sn` catches your command before the real Node.js binaries see it.
2. **Dry Run Simulation**: It executes `npm install <packages> --dry-run --json`. This forces NPM to resolve the entire dependency tree without actually downloading or executing anything.
3. **JSON Parsing**: It passes the resulting data to `jq` to extract a clean list of every single package and exact version that will be added or updated.
4. **Local Cache Check**: It checks `~/.cache/safe-npm/` for the publication date of each version. If found, it skips the network request.
5. **Concurrent API Checks with Worker Control**: For uncached packages, it spins up parallel background processes (`&`). It monitors active process IDs to keep execution capped at a pool of **15 concurrent workers** to protect CPU limits and prevent HTTP 429 (rate-limiting) responses from the NPM registry.
6. **Evaluation**: It converts timestamps to UNIX epoch time and compares them to the configured threshold.

---

## Configuration & Maintenance

### Threshold
By default, the script flags any package newer than **7 days**. To change this, edit:
```bash
sudo nano /usr/local/lib/sn-core.sh
```
Change `NPM_SECURITY_DAYS=7` to your preferred number.

### Clearing the Cache
If you wish to clear the verification cache and force the script to re-check the registry for all packages:
```bash
rm -rf ~/.cache/safe-npm
```

---

## NVM Compatibility
`safe-npm` is fully compatible with NVM. However, because NVM places its binaries at the front of your `$PATH`, you must create a global shell function routing:

1. Open the global bashrc: `sudo nano /etc/bash.bashrc`
2. Paste at the bottom:
   ```bash
   npm() { /usr/local/bin/npm "$@"; }
   npx() { /usr/local/bin/npx "$@"; }
   ```
3. Restart your terminal.

## License
MIT License.
