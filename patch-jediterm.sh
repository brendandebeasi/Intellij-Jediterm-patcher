#!/bin/bash
#
# JediTerm Patcher for IntelliJ IDEA
# Builds latest JediTerm from source and patches IntelliJ installation
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

detect_intellij_paths() {
    local paths=()

    case "$(uname -s)" in
        Darwin)
            # macOS paths
            for app in "/Applications/IntelliJ IDEA.app" \
                       "/Applications/IntelliJ IDEA CE.app" \
                       "/Applications/IntelliJ IDEA Ultimate.app" \
                       "$HOME/Applications/IntelliJ IDEA.app" \
                       "$HOME/Applications/IntelliJ IDEA CE.app"; do
                if [[ -d "$app" ]]; then
                    paths+=("$app/Contents/lib")
                fi
            done
            ;;
        Linux)
            # Linux paths
            for dir in "/opt/idea" \
                       "/opt/intellij-idea" \
                       "/opt/jetbrains/idea" \
                       "/usr/local/idea" \
                       "/snap/intellij-idea-ultimate/current" \
                       "/snap/intellij-idea-community/current" \
                       "$HOME/.local/share/JetBrains/Toolbox/apps/IDEA-U/"*"/idea-"* \
                       "$HOME/.local/share/JetBrains/Toolbox/apps/IDEA-C/"*"/idea-"*; do
                if [[ -d "$dir" ]]; then
                    if [[ -d "$dir/lib" ]]; then
                        paths+=("$dir/lib")
                    fi
                fi
            done
            ;;
        MINGW*|CYGWIN*|MSYS*)
            # Windows paths
            for dir in "/c/Program Files/JetBrains/IntelliJ IDEA"* \
                       "/c/Program Files (x86)/JetBrains/IntelliJ IDEA"* \
                       "$LOCALAPPDATA/JetBrains/Toolbox/apps/IDEA-U/"*"/idea-"* \
                       "$LOCALAPPDATA/JetBrains/Toolbox/apps/IDEA-C/"*"/idea-"*; do
                if [[ -d "$dir" ]]; then
                    if [[ -d "$dir/lib" ]]; then
                        paths+=("$dir/lib")
                    fi
                fi
            done
            ;;
    esac

    printf '%s\n' "${paths[@]}"
}

check_java() {
    if ! command -v java &> /dev/null; then
        error "Java not found. Please install JDK 11 or higher."
    fi

    local java_version
    java_version=$(java -version 2>&1 | head -n1 | cut -d'"' -f2 | cut -d'.' -f1)
    if [[ "$java_version" -lt 11 ]]; then
        error "Java 11 or higher required. Found: $java_version"
    fi
    success "Java $java_version detected"
}

check_git() {
    if ! command -v git &> /dev/null; then
        error "Git not found. Please install git."
    fi
    success "Git detected"
}

clone_or_update_repo() {
    local repo_dir="$1"

    if [[ -d "$repo_dir/.git" ]]; then
        info "Updating existing JediTerm repository..."
        cd "$repo_dir"
        git fetch origin
        git reset --hard origin/master
        success "Repository updated"
    elif [[ -d "$repo_dir" ]] && [[ -z "$(ls -A "$repo_dir" 2>/dev/null)" ]]; then
        info "Cloning JediTerm into empty directory..."
        git clone https://github.com/JetBrains/jediterm.git "$repo_dir"
        success "Repository cloned"
    elif [[ -d "$repo_dir" ]]; then
        # Directory exists and is not empty, clone into subdirectory
        info "Cloning JediTerm into $repo_dir/jediterm..."
        git clone https://github.com/JetBrains/jediterm.git "$repo_dir/jediterm"
        repo_dir="$repo_dir/jediterm"
        success "Repository cloned"
    else
        info "Cloning JediTerm repository..."
        mkdir -p "$repo_dir"
        git clone https://github.com/JetBrains/jediterm.git "$repo_dir"
        success "Repository cloned"
    fi

    echo "$repo_dir"
}

build_jediterm() {
    local repo_dir="$1"

    info "Building JediTerm..."
    cd "$repo_dir"

    # Build only core and ui modules (skip demo app which may have compatibility issues)
    if ./gradlew :core:jar :ui:jar --no-daemon 2>&1 | tee /tmp/jediterm-build.log; then
        success "Build completed"
    else
        warn "Build with default settings failed, trying with test exclusions..."
        if ./gradlew :core:jar :ui:jar -x test -x compileTestKotlin -x compileTestJava --no-daemon 2>&1 | tee /tmp/jediterm-build.log; then
            success "Build completed (tests skipped)"
        else
            error "Build failed. Check /tmp/jediterm-build.log for details."
        fi
    fi
}

find_built_jars() {
    local repo_dir="$1"

    # Check both possible build output locations
    local core_jar ui_jar

    for build_dir in ".gradleBuild" "build"; do
        if [[ -f "$repo_dir/$build_dir/core/libs/"jediterm-core-*.jar ]]; then
            core_jar=$(ls "$repo_dir/$build_dir/core/libs/"jediterm-core-*.jar 2>/dev/null | grep -v sources | head -1)
            ui_jar=$(ls "$repo_dir/$build_dir/ui/libs/"jediterm-ui-*.jar 2>/dev/null | grep -v sources | head -1)
            break
        fi
        if [[ -f "$repo_dir/core/$build_dir/libs/"jediterm-core-*.jar ]]; then
            core_jar=$(ls "$repo_dir/core/$build_dir/libs/"jediterm-core-*.jar 2>/dev/null | grep -v sources | head -1)
            ui_jar=$(ls "$repo_dir/ui/$build_dir/libs/"jediterm-ui-*.jar 2>/dev/null | grep -v sources | head -1)
            break
        fi
    done

    if [[ -z "$core_jar" ]] || [[ -z "$ui_jar" ]]; then
        error "Could not find built JAR files. Build may have failed."
    fi

    echo "$core_jar"
    echo "$ui_jar"
}

patch_intellij() {
    local intellij_lib="$1"
    local core_jar="$2"
    local ui_jar="$3"

    local lib_client="$intellij_lib/lib-client.jar"

    if [[ ! -f "$lib_client" ]]; then
        error "lib-client.jar not found at $lib_client"
    fi

    # Create backup
    local backup="$lib_client.bak"
    if [[ ! -f "$backup" ]]; then
        info "Creating backup of lib-client.jar..."
        cp "$lib_client" "$backup"
        success "Backup created: $backup"
    else
        warn "Backup already exists: $backup"
    fi

    # Create temp directory for extraction
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    info "Extracting new JediTerm classes..."
    cd "$temp_dir"
    unzip -q "$core_jar"
    unzip -q -o "$ui_jar"

    local class_count
    class_count=$(find com/jediterm -name "*.class" 2>/dev/null | wc -l | tr -d ' ')
    info "Found $class_count classes to patch"

    info "Patching lib-client.jar..."
    zip -r "$lib_client" com/jediterm/ > /dev/null

    success "Patch applied successfully!"

    # Show version info
    local new_size old_size
    new_size=$(wc -c < "$lib_client" | tr -d ' ')
    old_size=$(wc -c < "$backup" | tr -d ' ')

    echo ""
    info "Original size: $old_size bytes"
    info "Patched size:  $new_size bytes"
}

print_banner() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   JediTerm Patcher for IntelliJ IDEA   ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --repo PATH       Path to clone/update JediTerm repository"
    echo "  -i, --intellij PATH   Path to IntelliJ lib directory"
    echo "  -h, --help            Show this help message"
    echo "  --revert              Revert to original lib-client.jar from backup"
    echo ""
}

revert_patch() {
    local intellij_lib="$1"
    local lib_client="$intellij_lib/lib-client.jar"
    local backup="$lib_client.bak"

    if [[ ! -f "$backup" ]]; then
        error "No backup found at $backup"
    fi

    info "Reverting to original lib-client.jar..."
    cp "$backup" "$lib_client"
    success "Reverted successfully!"
}

main() {
    local repo_dir=""
    local intellij_lib=""
    local do_revert=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--repo)
                repo_dir="$2"
                shift 2
                ;;
            -i|--intellij)
                intellij_lib="$2"
                shift 2
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            --revert)
                do_revert=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    print_banner

    # Check prerequisites
    check_git
    check_java
    echo ""

    # Detect IntelliJ installations
    if [[ -z "$intellij_lib" ]]; then
        info "Detecting IntelliJ IDEA installations..."

        mapfile -t detected_paths < <(detect_intellij_paths)

        if [[ ${#detected_paths[@]} -eq 0 ]]; then
            warn "No IntelliJ installations auto-detected."
            echo ""
            read -rp "Enter path to IntelliJ lib directory: " intellij_lib
        elif [[ ${#detected_paths[@]} -eq 1 ]]; then
            intellij_lib="${detected_paths[0]}"
            success "Found: $intellij_lib"
            read -rp "Use this installation? [Y/n] " confirm
            if [[ "$confirm" =~ ^[Nn] ]]; then
                read -rp "Enter path to IntelliJ lib directory: " intellij_lib
            fi
        else
            echo "Multiple installations found:"
            for i in "${!detected_paths[@]}"; do
                echo "  $((i+1))) ${detected_paths[$i]}"
            done
            echo "  0) Enter custom path"
            echo ""
            read -rp "Select installation [1]: " selection
            selection=${selection:-1}

            if [[ "$selection" -eq 0 ]]; then
                read -rp "Enter path to IntelliJ lib directory: " intellij_lib
            else
                intellij_lib="${detected_paths[$((selection-1))]}"
            fi
        fi
    fi

    # Validate IntelliJ path
    if [[ ! -d "$intellij_lib" ]]; then
        error "Directory not found: $intellij_lib"
    fi

    if [[ ! -f "$intellij_lib/lib-client.jar" ]]; then
        error "lib-client.jar not found in $intellij_lib"
    fi

    success "Using IntelliJ lib: $intellij_lib"
    echo ""

    # Handle revert
    if [[ "$do_revert" == true ]]; then
        revert_patch "$intellij_lib"
        exit 0
    fi

    # Get repo directory
    if [[ -z "$repo_dir" ]]; then
        local default_repo="$HOME/jediterm"
        read -rp "Directory for JediTerm source [$default_repo]: " repo_dir
        repo_dir=${repo_dir:-$default_repo}
    fi

    # Expand ~ if present
    repo_dir="${repo_dir/#\~/$HOME}"

    echo ""

    # Clone or update repository
    repo_dir=$(clone_or_update_repo "$repo_dir")
    echo ""

    # Build
    build_jediterm "$repo_dir"
    echo ""

    # Find built JARs
    info "Locating built JAR files..."
    mapfile -t jars < <(find_built_jars "$repo_dir")
    core_jar="${jars[0]}"
    ui_jar="${jars[1]}"
    success "Core JAR: $core_jar"
    success "UI JAR:   $ui_jar"
    echo ""

    # Patch
    patch_intellij "$intellij_lib" "$core_jar" "$ui_jar"

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}            Patch Complete!             ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Quit IntelliJ IDEA completely (Cmd+Q / Alt+F4)"
    echo "  2. Restart IntelliJ IDEA"
    echo "  3. Test in terminal: echo -n \"0123456789\" && echo -ne \"\\e[5 q\""
    echo ""
    echo "To revert: $0 --revert -i \"$intellij_lib\""
    echo ""
}

main "$@"
