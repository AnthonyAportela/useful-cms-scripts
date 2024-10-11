#!/bin/bash

# Define the EL versions to test
EL_VERSIONS=("el5" "el6" "el7" "el8" "el9")

WORKING_DIR="/home/users/aaportel/CMSSWs"

# Define a directory to temporarily clone the repositories
TEMP_REPO_DIR="/tmp/cmssw_repos"

# Define output files (use an absolute path for the logs)
SUMMARY_FILE="/tmp/cmssw_compile_summary.txt"
LOG_DIR="/tmp/cmssw_compile_logs"

# Initialize the summary file
echo "CMSSW Compilation Summary" > "${SUMMARY_FILE}"
echo "=========================" >> "${SUMMARY_FILE}"

# Create the log directory if it doesn't exist
mkdir -p "${LOG_DIR}"

# Function to handle cleanup and graceful shutdown
function cleanup() {
    echo "Cleaning up..."
    cp -r "${SUMMARY_FILE}" "${WORKING_DIR}"
    cp -r "${LOG_DIR}" "${WORKING_DIR}"
    #rm -rf "${TEMP_REPO_DIR}"
    echo "Deleted temporary repository directory."
    echo "Exiting."
    exit 1
}

# Trap interrupts (like Ctrl+C) and call cleanup
trap cleanup SIGINT SIGTERM

# Clone the repositories once into the temporary directory with specific paths
function clone_repositories_once() {
    if [ ! -d "$TEMP_REPO_DIR" ]; then
        echo "Creating temporary repository directory: ${TEMP_REPO_DIR}"
        mkdir -p "${TEMP_REPO_DIR}"

        cd "${TEMP_REPO_DIR}"
        
        echo "Cloning repositories into the temporary directory..."

        git clone "https://github.com/cms-lpc-llp/JetToolbox.git" "JMEAnalysis/JetToolbox"
        cd "JMEAnalysis/JetToolbox"; git checkout "jetToolbox_91X"; cd -;
        git clone "https://github.com/cms-lpc-llp/llp_ntupler.git" "cms_lpc_llp/llp_ntupler"
        cd "cms_lpc_llp/llp_ntupler"; git checkout "HeavyIonRun2"; cd -;
        git clone "https://github.com/AnthonyAportela/pedro_llp-ntupler.git"
        
        rm -rf "${TEMP_REPO_DIR}/pedro_llp-ntupler/.git/"
        cp -r "${TEMP_REPO_DIR}/pedro_llp-ntupler/"* .
        rm -rf "${TEMP_REPO_DIR}/pedro_llp-ntupler/"

        cd "${WORKING_DIR}"

        echo "Finished cloning repositories into ${TEMP_REPO_DIR}"
    else
        echo "Repositories already cloned in ${TEMP_REPO_DIR}. Skipping clone."
    fi
}

# Function to get CMSSW versions for a specific EL version, cmsrel them, and copy repos
function get_cmssw_versions() {
    EL_VERSION=$1
    echo "Testing EL version: ${EL_VERSION}"

    # Set the helper script path
    HELPER_SCRIPT="/cvmfs/cms.cern.ch/common/cmssw-${EL_VERSION}"

    # Check if the helper script exists and is executable
    if [ ! -x "$HELPER_SCRIPT" ]; then
        echo "Helper script $HELPER_SCRIPT not found or not executable. Skipping..."
        return
    fi

    # Run the helper script in a subshell to prevent environment variable leakage
    (
        # Inside this subshell, environment variable changes will not affect the parent shell

        # Add debug output to see the actual command being run
        echo "Running: $HELPER_SCRIPT -- bash -c 'scram list CMSSW'"

        # Run the command and capture CMSSW versions
        CMSSW_VERSIONS=$("$HELPER_SCRIPT" -- bash -c 'scram list CMSSW' 2>&1 | grep -oP 'CMSSW_\d+_\d+_\d+$')

        # Check if the command succeeded
        if [ $? -ne 0 ]; then
            echo "Error running scram list CMSSW for $EL_VERSION"
            exit 1
        fi

        # Loop through each CMSSW version and run cmsrel, cmsenv, and scram in one line
        for VERSION in ${CMSSW_VERSIONS}; do
            echo "Running cmsrel for ${VERSION}"

            # Run everything in one single line inside the Singularity environment
            "$HELPER_SCRIPT" -- bash -c "cmsrel ${VERSION} && cd ${VERSION}/src && cp -r ${TEMP_REPO_DIR}/* . && cmsenv && scram b -j40" 2> "${LOG_DIR}/${VERSION}_${EL_VERSION}_compile.log"

            # Check if the process succeeded
            if [ $? -ne 0 ]; then
                echo "Error in cmsrel/cmsenv/compile for ${VERSION} on ${EL_VERSION}. Check ${LOG_DIR}/${VERSION}_${EL_VERSION}_compile.log"
                echo "${VERSION} on ${EL_VERSION}: FAILED" >> "${SUMMARY_FILE}"
                # Remove the CMSSW directory if compilation failed
                rm -rf "${VERSION}"
            else
                echo "Successfully completed cmsrel, cmsenv, and compilation for ${VERSION} on ${EL_VERSION}"
                echo "${VERSION} on ${EL_VERSION}: SUCCESS" >> "${SUMMARY_FILE}"
                # Remove log file if compilation succeeded
                rm -f "${LOG_DIR}/${VERSION}_${EL_VERSION}_compile.log"
            fi
        done
    )
    # End of subshell - any environment changes inside are discarded here
}

# First, clone repositories once into the temporary directory
clone_repositories_once
if [ $? -ne 0 ]; then
    echo "Failed to clone repositories. Exiting."
    cleanup
fi

# Loop over EL versions
for EL_VERSION in "${EL_VERSIONS[@]}"; do
    get_cmssw_versions "${EL_VERSION}"
done

# Cleanup after successful run
cleanup

echo "Compilation summary saved to ${SUMMARY_FILE}"
