# IntelliJ JediTerm Patcher

Patch IntelliJ IDEA with the latest [JediTerm](https://github.com/JetBrains/jediterm) terminal emulator from source to get unreleased bug fixes and improvements.

## Why?

JetBrains bundles JediTerm (their terminal emulator library) inside IntelliJ IDEA, but releases can lag behind the source repository. This script lets you build the latest JediTerm and patch your IntelliJ installation to get fixes before they ship officially.

### Recent Fixes Available via Patching

| Fix | Issue | Description |
|-----|-------|-------------|
| Cursor shape change bug | [IJPL-211845](https://youtrack.jetbrains.com/issue/IJPL-211845) | Characters disappeared when cursor shape changed |
| Touchpad scroll handling | [#312](https://github.com/JetBrains/jediterm/pull/312) | Improved scroll event handling |
| ED command fix | [#309](https://github.com/JetBrains/jediterm/pull/309) | Screen clearing now works on last line |
| Private mode sequences | [#313](https://github.com/JetBrains/jediterm/issues/313) | CSI ? sequences handled correctly |

## Requirements

- **Git** - to clone the JediTerm repository
- **JDK 11+** - to build JediTerm (JDK 17+ recommended)
- **IntelliJ IDEA** - Ultimate or Community Edition

## Installation

```bash
# Clone this repo
git clone git@github.com:brendandebeasi/Intellij-Jediterm-patcher.git
cd Intellij-Jediterm-patcher

# Make executable
chmod +x patch-jediterm.sh
```

## Usage

### Interactive Mode (Recommended)

```bash
./patch-jediterm.sh
```

The script will:
1. Detect your IntelliJ installation(s)
2. Ask where to clone/update the JediTerm source
3. Build JediTerm
4. Patch IntelliJ's `lib-client.jar`

### Command Line Arguments

```bash
# Specify paths directly
./patch-jediterm.sh -r ~/dev/jediterm -i "/Applications/IntelliJ IDEA.app/Contents/lib"

# Revert to original
./patch-jediterm.sh --revert -i "/Applications/IntelliJ IDEA.app/Contents/lib"

# Show help
./patch-jediterm.sh --help
```

### Options

| Option | Description |
|--------|-------------|
| `-r, --repo PATH` | Path to clone/update JediTerm repository |
| `-i, --intellij PATH` | Path to IntelliJ's `lib` directory |
| `--revert` | Restore original `lib-client.jar` from backup |
| `-h, --help` | Show help message |

## Manual Installation

If you prefer not to use the script, follow these steps:

### Step 1: Clone and Build JediTerm

```bash
# Clone the repository
git clone https://github.com/JetBrains/jediterm.git
cd jediterm

# Build core and ui modules (skip tests to avoid JDK compatibility issues)
./gradlew :core:jar :ui:jar

# Find the built JARs - check both possible locations
ls .gradleBuild/core/libs/jediterm-core-*.jar 2>/dev/null || ls core/build/libs/jediterm-core-*.jar
ls .gradleBuild/ui/libs/jediterm-ui-*.jar 2>/dev/null || ls ui/build/libs/jediterm-ui-*.jar
```

### Step 2: Locate IntelliJ's lib-client.jar

Find your IntelliJ installation:

**macOS:**
```bash
# Ultimate Edition
ls "/Applications/IntelliJ IDEA.app/Contents/lib/lib-client.jar"

# Community Edition
ls "/Applications/IntelliJ IDEA CE.app/Contents/lib/lib-client.jar"
```

**Linux:**
```bash
# Common locations
ls /opt/idea/lib/lib-client.jar
ls /opt/intellij-idea/lib/lib-client.jar
ls ~/.local/share/JetBrains/Toolbox/apps/IDEA-U/*/lib/lib-client.jar
```

**Windows (PowerShell):**
```powershell
# Common locations
dir "C:\Program Files\JetBrains\IntelliJ IDEA *\lib\lib-client.jar"
dir "$env:LOCALAPPDATA\JetBrains\Toolbox\apps\IDEA-U\*\lib\lib-client.jar"
```

### Step 3: Backup the Original JAR

**macOS/Linux:**
```bash
INTELLIJ_LIB="/Applications/IntelliJ IDEA.app/Contents/lib"  # Adjust path as needed

cp "$INTELLIJ_LIB/lib-client.jar" "$INTELLIJ_LIB/lib-client.jar.bak"
```

**Windows (PowerShell):**
```powershell
$intellijLib = "C:\Program Files\JetBrains\IntelliJ IDEA 2024.1\lib"  # Adjust path

Copy-Item "$intellijLib\lib-client.jar" "$intellijLib\lib-client.jar.bak"
```

### Step 4: Extract and Patch

**macOS/Linux:**
```bash
# Set paths (adjust as needed)
INTELLIJ_LIB="/Applications/IntelliJ IDEA.app/Contents/lib"
JEDITERM_DIR="$HOME/jediterm"

# Create temp directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Extract new JediTerm classes (check which build dir exists)
if [ -d "$JEDITERM_DIR/.gradleBuild" ]; then
    unzip -q "$JEDITERM_DIR/.gradleBuild/core/libs/"jediterm-core-*.jar
    unzip -q -o "$JEDITERM_DIR/.gradleBuild/ui/libs/"jediterm-ui-*.jar
else
    unzip -q "$JEDITERM_DIR/core/build/libs/"jediterm-core-*.jar
    unzip -q -o "$JEDITERM_DIR/ui/build/libs/"jediterm-ui-*.jar
fi

# Patch lib-client.jar with new classes
zip -r "$INTELLIJ_LIB/lib-client.jar" com/jediterm/

# Cleanup
cd -
rm -rf "$TEMP_DIR"

echo "Done! Restart IntelliJ IDEA to apply changes."
```

**Windows (PowerShell):**
```powershell
# Set paths (adjust as needed)
$intellijLib = "C:\Program Files\JetBrains\IntelliJ IDEA 2024.1\lib"
$jeditermDir = "$env:USERPROFILE\jediterm"

# Create temp directory
$tempDir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_ }
Set-Location $tempDir

# Extract new JediTerm classes
Expand-Archive -Path "$jeditermDir\.gradleBuild\core\libs\jediterm-core-*.jar" -DestinationPath .
Expand-Archive -Path "$jeditermDir\.gradleBuild\ui\libs\jediterm-ui-*.jar" -DestinationPath . -Force

# Use 7-Zip or jar command to update the JAR (PowerShell's Compress-Archive won't update)
# Option 1: Using jar (requires JDK)
jar -uf "$intellijLib\lib-client.jar" -C . com/jediterm

# Option 2: Using 7-Zip
# & "C:\Program Files\7-Zip\7z.exe" u "$intellijLib\lib-client.jar" "com\jediterm\*"

# Cleanup
Set-Location $env:USERPROFILE
Remove-Item -Recurse -Force $tempDir

Write-Host "Done! Restart IntelliJ IDEA to apply changes."
```

### Step 5: Restart and Verify

1. Quit IntelliJ IDEA completely
2. Restart IntelliJ IDEA
3. Open a terminal and run:
   ```bash
   echo -n "0123456789" && echo -ne "\e[5 q" && echo " <-- All 10 chars visible?"
   ```

### Manual Revert

**macOS/Linux:**
```bash
INTELLIJ_LIB="/Applications/IntelliJ IDEA.app/Contents/lib"
cp "$INTELLIJ_LIB/lib-client.jar.bak" "$INTELLIJ_LIB/lib-client.jar"
```

**Windows (PowerShell):**
```powershell
$intellijLib = "C:\Program Files\JetBrains\IntelliJ IDEA 2024.1\lib"
Copy-Item "$intellijLib\lib-client.jar.bak" "$intellijLib\lib-client.jar" -Force
```

---

## How It Works

### The Problem

IntelliJ IDEA bundles JediTerm classes directly inside `lib-client.jar` (a ~100MB JAR containing many libraries). Unlike older versions that had separate `jediterm-core.jar` and `jediterm-ui.jar` files, modern IntelliJ embeds everything.

### The Solution

1. **Clone/Update** - Fetches latest JediTerm source from GitHub
2. **Build** - Compiles `jediterm-core` and `jediterm-ui` modules using Gradle
3. **Extract** - Unpacks the built JAR files to get compiled `.class` files
4. **Patch** - Uses `zip -r` to update `lib-client.jar` with new classes (replacing existing `com/jediterm/*` entries)
5. **Backup** - Creates `lib-client.jar.bak` before patching (only on first run)

### File Locations

| OS | IntelliJ lib directory |
|----|----------------------|
| macOS | `/Applications/IntelliJ IDEA.app/Contents/lib/` |
| Linux | `/opt/idea/lib/` or `~/.local/share/JetBrains/Toolbox/apps/IDEA-*/lib/` |
| Windows | `C:\Program Files\JetBrains\IntelliJ IDEA *\lib\` |

## Verification

After patching and restarting IntelliJ, test in the terminal:

```bash
# This should show all 10 characters - the 'J' would disappear with the old bug
echo -n "0123456789" && echo -ne "\e[5 q" && echo " <-- All 10 chars visible?"
```

Test cursor shape changes:
```bash
echo -e "\e[1 q"  # Blinking block
echo -e "\e[3 q"  # Blinking underline
echo -e "\e[5 q"  # Blinking bar
echo -e "\e[0 q"  # Reset to default
```

## Reverting

If something goes wrong:

```bash
# Using the script
./patch-jediterm.sh --revert -i "/Applications/IntelliJ IDEA.app/Contents/lib"

# Or manually
cp "/Applications/IntelliJ IDEA.app/Contents/lib/lib-client.jar.bak" \
   "/Applications/IntelliJ IDEA.app/Contents/lib/lib-client.jar"
```

## Updating

Run the script again after pulling new JediTerm changes:

```bash
./patch-jediterm.sh -r ~/dev/jediterm
```

The script will `git fetch` and `git reset --hard origin/master` to get the latest code.

## Troubleshooting

### Build fails with Kotlin/Java version mismatch

The script automatically skips tests which often have compatibility issues with newer JDKs. If the build still fails:

```bash
# Try with a specific JDK version
export JAVA_HOME=/path/to/jdk17
./patch-jediterm.sh
```

### IntelliJ won't start after patching

Revert to the backup:
```bash
./patch-jediterm.sh --revert -i "/path/to/intellij/lib"
```

### Permission denied on macOS

The script may need elevated permissions for system-wide IntelliJ installations:
```bash
sudo ./patch-jediterm.sh
```

### IntelliJ update overwrites patch

IntelliJ updates replace `lib-client.jar`. Simply re-run the script after updating:
```bash
./patch-jediterm.sh
```

## Warnings

- **Backup your work** - This modifies your IntelliJ installation
- **Not officially supported** - Use at your own risk
- **Updates overwrite** - IntelliJ updates will replace the patch
- **Test thoroughly** - Verify terminal functionality after patching

## Platform Support

| Platform | Status |
|----------|--------|
| macOS (Intel/ARM) | Tested |
| Linux | Should work (auto-detects common paths) |
| Windows (Git Bash) | Should work (auto-detects common paths) |

## License

MIT License - see [LICENSE](LICENSE)

## Contributing

Issues and PRs welcome! Please test on your platform before submitting.

## Related

- [JediTerm](https://github.com/JetBrains/jediterm) - The terminal emulator library
- [IntelliJ IDEA](https://www.jetbrains.com/idea/) - The IDE
- [JetBrains YouTrack](https://youtrack.jetbrains.com/) - Bug tracker for IntelliJ issues
