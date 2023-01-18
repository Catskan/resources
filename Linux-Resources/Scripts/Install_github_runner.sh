runner_name=github-actions-runner
runner_version=2.300.2
cpu_model_Apple="Apple M1"
kernel="$(sysctl -a | grep -E 'ostype' | awk '{print $2, $3}')"

# Create a folder
mkdir $HOME/$runner_name && cd $HOME/$runner_name
# Download the latest runner package
case $kernel in
    *"Linux"*)
        echo "It's Linux"
        os_type=linux
        curl -o $HOME/$runner_name/$runner_name-$os_type-$runner_version.tar.gz -L https://github.com/actions/runner/releases/download/v$runner_version/actions-runner-linux-x64-$runner_version.tar.gz
;;
    *"Darwin"*)
        echo "It's MacOS"
        os=MacOS
        if [ "$(sysctl -n machdep.cpu.brand_string)" = 'Apple M1' ]
        then
            arch="arm64"
        fi
            curl -o $HOME/$runner_name/$runner_name-$os_type-$runner_version.tar.gz -L https://github.com/actions/runner/releases/download/v$runner_version/actions-runner-osx-$arch-$runner_version.tar.gz
;;
esac
# Optional: Validate the hash
echo "147c14700c6cb997421b9a239c012197f11ea9854cd901ee88ead6fe73a72c74  $HOME/$runner_name/$runner_name-$os_type-$runner_version.tar.gz" | shasum -a 256 -c
# Extract the installer
tar xzf $HOME/$runner_name/$runner_name-$os_type-$runner_version.tar.gz --directory $HOME/$runner_name
# Create the runner and start the configuration experience
$HOME/$runner_name/config.sh --url https://github.com/Catskan/resources --token $GITHUB_TOKEN --unattended
# Last step, run it!
$HOME/$runner_name/run.sh