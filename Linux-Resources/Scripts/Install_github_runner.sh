runner_name=github-actions-runner
runner_version=2.299.1
cpu_model_Apple="Apple M1"
kernel="$(sysctl -a | grep -E 'ostype' | awk '{print $2, $3}')"
# Create a folder
mkdir $runner_name && cd $runner_name
# Download the latest runner package
case $kernel in
    *"Linux"*)
        echo "It's Linux"
        os_type=linux
        curl -o $runner_name-$os_type-$runner_version.tar.gz -L https://github.com/actions/runner/releases/download/v2.299.1/actions-runner-linux-x64-$runner_version.tar.gz
;;
    *"Darwin"*)
        echo "It's MacOS"
        os_type=macOS
        curl -o $runner_name-$os_type-$runner_version.tar.gz -L https://github.com/actions/runner/releases/download/v2.300.2/actions-runner-osx-arm64-$runner_version.tar.gz
;;
esac
# Optional: Validate the hash
echo "147c14700c6cb997421b9a239c012197f11ea9854cd901ee88ead6fe73a72c74  $runner_name-$os_type-$runner_version.tar.gz" | shasum -a 256 -c
# Extract the installer
tar xzf ./$runner_name-$os_type-$runner_version.tar.gz
# Create the runner and start the configuration experience
./config.sh --url https://github.com/Catskan/resources --token $GITHUB_TOKEN
# Last step, run it!
./run.sh