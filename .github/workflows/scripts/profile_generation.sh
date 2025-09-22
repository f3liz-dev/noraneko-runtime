#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
#
# Profile Generation Script for PGO (Profile-Guided Optimization)
# This script handles profile data generation for both Linux and Windows platforms

set -e

# Default values
TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-1200}
XVFB_DISPLAY=${XVFB_DISPLAY:-:99}
XVFB_SCREEN=${XVFB_SCREEN:-"1280x1024x24"}

# Function to show usage
usage() {
    echo "Usage: $0 [OPTIONS] --binary BINARY_PATH"
    echo ""
    echo "Options:"
    echo "  --binary PATH          Path to the browser binary (required)"
    echo "  --platform PLATFORM   Platform (linux, windows) - auto-detected if not provided"
    echo "  --timeout SECONDS     Timeout for profile generation (default: 1200)"
    echo "  --help                Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  BROWSER_BINARY_PATH   Alternative way to specify binary path"
    echo "  LLVM_PROFDATA         Path to llvm-profdata binary"
    echo "  JARLOG_FILE           Name of the jarlog file (default: en-US.log)"
    echo "  MOZ_LOG               Mozilla logging level (default: PGO:3)"
    exit 1
}

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Function to detect platform
detect_platform() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        Darwin*) echo "mac" ;;
        *) echo "unknown" ;;
    esac
}

# Function to find llvm-profdata
find_llvm_profdata() {
    local llvm_profdata_cmd=""
    
    if command -v llvm-profdata >/dev/null 2>&1; then
        llvm_profdata_cmd="llvm-profdata"
    else
        # Look in mozbuild directory
        local mozbuild_path="${HOME}/.mozbuild"
        if [[ -d "$mozbuild_path" ]]; then
            llvm_profdata_cmd=$(find "$mozbuild_path" -name "llvm-profdata*" -type f -executable 2>/dev/null | head -1)
        fi
        
        # Look in MOZ_FETCHES_DIR if available
        if [[ -z "$llvm_profdata_cmd" && -n "$MOZ_FETCHES_DIR" ]]; then
            llvm_profdata_cmd=$(find "$MOZ_FETCHES_DIR" -name "llvm-profdata*" -type f -executable 2>/dev/null | head -1)
        fi
        
        # Windows-specific paths
        if [[ -z "$llvm_profdata_cmd" && "$PLATFORM" == "windows" ]]; then
            # Check common Windows locations
            local win_paths=(
                "/c/Users/runneradmin/.mozbuild/clang/bin/llvm-profdata.exe"
                "/c/mozilla-build/msys2/clang64/bin/llvm-profdata.exe"
            )
            
            for path in "${win_paths[@]}"; do
                if [[ -f "$path" ]]; then
                    llvm_profdata_cmd="$path"
                    break
                fi
            done
            
            # Search in .mozbuild for Windows
            if [[ -z "$llvm_profdata_cmd" ]]; then
                llvm_profdata_cmd=$(find /c/Users/runneradmin/.mozbuild -name "llvm-profdata.exe" -type f 2>/dev/null | head -1)
            fi
        fi
        
        if [[ -z "$llvm_profdata_cmd" ]]; then
            log "Warning: llvm-profdata not found, using system default"
            llvm_profdata_cmd="llvm-profdata"
        fi
    fi
    
    echo "$llvm_profdata_cmd"
}

# Function to setup X11 display for Linux
setup_xvfb() {
    if [[ "$PLATFORM" == "linux" ]]; then
        log "Setting up X11 display for profile generation..."
        
        export DISPLAY="$XVFB_DISPLAY"
        export LIBGL_ALWAYS_SOFTWARE=1
        export MOZ_HEADLESS=1
        export MOZ_DISABLE_CONTENT_SANDBOX=1
        
        log "Starting Xvfb..."
        Xvfb "$XVFB_DISPLAY" -screen 0 "$XVFB_SCREEN" -extension GLX -extension RANDR &
        XVFB_PID=$!
        sleep 5
        
        if ! kill -0 $XVFB_PID 2>/dev/null; then
            log "ERROR: Xvfb failed to start"
            exit 1
        fi
        
        log "Xvfb started successfully with PID: $XVFB_PID"
    elif [[ "$PLATFORM" == "windows" ]]; then
        log "Setting up Windows environment for profile generation..."
        
        # Windows doesn't need Xvfb but may need display setup
        export DISPLAY="${DISPLAY:-:0}"
        export MOZ_HEADLESS=1
        export MOZ_DISABLE_CONTENT_SANDBOX=1
    fi
}

# Function to cleanup X11 display
cleanup_xvfb() {
    if [[ -n "$XVFB_PID" ]]; then
        log "Stopping Xvfb (PID: $XVFB_PID)..."
        kill $XVFB_PID 2>/dev/null || true
        wait $XVFB_PID 2>/dev/null || true
    fi
}

# Function to run profile generation
run_profile_generation() {
    local binary_path="$1"
    local llvm_profdata_cmd="$2"
    
    # Verify profileserver.py exists
    if [[ ! -f "build/pgo/profileserver.py" ]]; then
        log "ERROR: profileserver.py not found"
        find . -name "*profileserver*" -type f || log "No profileserver files found"
        exit 1
    fi
    
    # Set environment variables
    export LLVM_PROFDATA="$llvm_profdata_cmd"
    export JARLOG_FILE="${JARLOG_FILE:-en-US.log}"
    export MOZ_LOG="${MOZ_LOG:-PGO:3}"
    
    log "Running profile generation with binary: $binary_path"
    log "Using LLVM_PROFDATA: $llvm_profdata_cmd"
    log "JARLOG_FILE: $JARLOG_FILE"
    log "Timeout: ${TIMEOUT_SECONDS}s"
    
    set -x
    
    timeout "$TIMEOUT_SECONDS" python3 build/pgo/profileserver.py --binary "$binary_path" || {
        local exit_code=$?
        log "Profile generation failed with exit code: $exit_code"
        
        cleanup_xvfb
        
        log "Checking for partial results..."
        ls -la *.profdata *.log 2>/dev/null || log "No profile files found"
        
        if [[ $exit_code -eq 124 ]]; then
            log "Profile generation timed out after $((TIMEOUT_SECONDS / 60)) minutes"
        fi
        
        exit 1
    }
    
    set +x
}

# Function to verify generated files
verify_profile_data() {
    log "Verifying generated profile data..."
    
    if [[ -f "merged.profdata" && -f "$JARLOG_FILE" ]]; then
        local profdata_size
        local jarlog_size
        
        # Get file sizes (different commands for different platforms)
        if command -v stat >/dev/null 2>&1; then
            if stat -c%s "merged.profdata" >/dev/null 2>&1; then
                # GNU stat (Linux)
                profdata_size=$(stat -c%s "merged.profdata" 2>/dev/null || echo "0")
                jarlog_size=$(stat -c%s "$JARLOG_FILE" 2>/dev/null || echo "0")
            else
                # BSD stat (macOS) or fallback
                profdata_size=$(stat -f%z "merged.profdata" 2>/dev/null || echo "0")
                jarlog_size=$(stat -f%z "$JARLOG_FILE" 2>/dev/null || echo "0")
            fi
        else
            # Fallback using ls
            profdata_size=$(ls -l "merged.profdata" 2>/dev/null | awk '{print $5}' || echo "0")
            jarlog_size=$(ls -l "$JARLOG_FILE" 2>/dev/null | awk '{print $5}' || echo "0")
        fi
        
        log "Profile generation successful!"
        log "  merged.profdata: $profdata_size bytes"
        log "  $JARLOG_FILE: $jarlog_size bytes"
        
        if [[ $profdata_size -eq 0 ]]; then
            log "WARNING: merged.profdata is empty"
        fi
        if [[ $jarlog_size -eq 0 ]]; then
            log "WARNING: $JARLOG_FILE is empty"
        fi
        
        return 0
    else
        log "ERROR: Profile generation failed - required files not found"
        log "Current directory contents:"
        ls -la . | grep -E "(profdata|log)" || log "No profile files found"
        return 1
    fi
}

# Main function
main() {
    local binary_path=""
    local platform=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --binary)
                binary_path="$2"
                shift 2
                ;;
            --platform)
                platform="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT_SECONDS="$2"
                shift 2
                ;;
            --help)
                usage
                ;;
            *)
                log "Unknown option: $1"
                usage
                ;;
        esac
    done
    
    # Use environment variable if binary path not provided
    if [[ -z "$binary_path" ]]; then
        binary_path="$BROWSER_BINARY_PATH"
    fi
    
    # Validate required parameters
    if [[ -z "$binary_path" ]]; then
        log "ERROR: Browser binary path is required"
        usage
    fi
    
    if [[ ! -f "$binary_path" ]]; then
        log "ERROR: Browser binary not found at: $binary_path"
        exit 1
    fi
    
    # Auto-detect platform if not provided
    if [[ -z "$platform" ]]; then
        platform=$(detect_platform)
    fi
    
    export PLATFORM="$platform"
    log "Starting profile generation for $platform platform"
    log "Binary: $binary_path"
    
    # Change to workspace directory if available
    if [[ -n "$GITHUB_WORKSPACE" ]]; then
        cd "$GITHUB_WORKSPACE"
        log "Working directory: $GITHUB_WORKSPACE"
    fi
    
    # Find llvm-profdata
    local llvm_profdata_cmd
    llvm_profdata_cmd=$(find_llvm_profdata)
    
    # Setup trap for cleanup
    trap cleanup_xvfb EXIT INT TERM
    
    # Setup platform-specific environment
    setup_xvfb
    
    # Run profile generation
    run_profile_generation "$binary_path" "$llvm_profdata_cmd"
    
    # Cleanup
    cleanup_xvfb
    
    # Verify results
    verify_profile_data
    
    log "Profile generation completed successfully"
}

# Run main function
main "$@"