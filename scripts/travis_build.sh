#!/bin/bash
source /etc/profile

if [[ -s ~/.bash_profile ]] ; then
  source ~/.bash_profile
fi

ANSI_RED="\033[31;1m"
ANSI_GREEN="\033[32;1m"
ANSI_RESET="\033[0m"
ANSI_CLEAR="\033[0K"

TRAVIS_TEST_RESULT=
TRAVIS_CMD=

function travis_cmd() {
  local assert output display retry timing cmd result

  cmd=$1
  TRAVIS_CMD=$cmd
  shift

  while true; do
    case "$1" in
      --assert)  assert=true; shift ;;
      --echo)    output=true; shift ;;
      --display) display=$2;  shift 2;;
      --retry)   retry=true;  shift ;;
      --timing)  timing=true; shift ;;
      *) break ;;
    esac
  done

  if [[ -n "$timing" ]]; then
    travis_time_start
  fi

  if [[ -n "$output" ]]; then
    echo "\$ ${display:-$cmd}"
  fi

  if [[ -n "$retry" ]]; then
    travis_retry eval "$cmd"
  else
    eval "$cmd"
  fi
  result=$?

  if [[ -n "$timing" ]]; then
    travis_time_finish
  fi

  if [[ -n "$assert" ]]; then
    travis_assert $result
  fi

  return $result
}

travis_time_start() {
  travis_timer_id=$(printf %08x $(( RANDOM * RANDOM )))
  travis_start_time=$(travis_nanoseconds)
  echo -en "travis_time:start:$travis_timer_id\r${ANSI_CLEAR}"
}

travis_time_finish() {
  local result=$?
  travis_end_time=$(travis_nanoseconds)
  local duration=$(($travis_end_time-$travis_start_time))
  echo -en "\ntravis_time:end:$travis_timer_id:start=$travis_start_time,finish=$travis_end_time,duration=$duration\r${ANSI_CLEAR}"
  return $result
}

function travis_nanoseconds() {
  local cmd="date"
  local format="+%s%N"
  local os=$(uname)

  if hash gdate > /dev/null 2>&1; then
    cmd="gdate" # use gdate if available
  elif [[ "$os" = Darwin ]]; then
    format="+%s000000000" # fallback to second precision on darwin (does not support %N)
  fi

  $cmd -u $format
}

travis_assert() {
  local result=${1:-$?}
  if [ $result -ne 0 ]; then
    echo -e "\n${ANSI_RED}The command \"$TRAVIS_CMD\" failed and exited with $result during $TRAVIS_STAGE.${ANSI_RESET}\n\nYour build has been stopped."
    travis_terminate 2
  fi
}

travis_result() {
  local result=$1
  export TRAVIS_TEST_RESULT=$(( ${TRAVIS_TEST_RESULT:-0} | $(($result != 0)) ))

  if [ $result -eq 0 ]; then
    echo -e "\n${ANSI_GREEN}The command \"$TRAVIS_CMD\" exited with $result.${ANSI_RESET}"
  else
    echo -e "\n${ANSI_RED}The command \"$TRAVIS_CMD\" exited with $result.${ANSI_RESET}"
  fi
}

travis_terminate() {
  pkill -9 -P $$ &> /dev/null || true
  exit $1
}

travis_wait() {
  local timeout=$1

  if [[ $timeout =~ ^[0-9]+$ ]]; then
    # looks like an integer, so we assume it's a timeout
    shift
  else
    # default value
    timeout=20
  fi

  local cmd="$@"
  local log_file=travis_wait_$$.log

  $cmd &>$log_file &
  local cmd_pid=$!

  travis_jigger $! $timeout $cmd &
  local jigger_pid=$!
  local result

  {
    wait $cmd_pid 2>/dev/null
    result=$?
    ps -p$jigger_pid &>/dev/null && kill $jigger_pid
  }

  if [ $result -eq 0 ]; then
    echo -e "\n${ANSI_GREEN}The command $cmd exited with $result.${ANSI_RESET}"
  else
    echo -e "\n${ANSI_RED}The command $cmd exited with $result.${ANSI_RESET}"
  fi

  echo -e "\n${ANSI_GREEN}Log:${ANSI_RESET}\n"
  cat $log_file

  return $result
}

travis_jigger() {
  # helper method for travis_wait()
  local cmd_pid=$1
  shift
  local timeout=$1 # in minutes
  shift
  local count=0

  # clear the line
  echo -e "\n"

  while [ $count -lt $timeout ]; do
    count=$(($count + 1))
    echo -ne "Still running ($count of $timeout): $@\r"
    sleep 60
  done

  echo -e "\n${ANSI_RED}Timeout (${timeout} minutes) reached. Terminating \"$@\"${ANSI_RESET}\n"
  kill -9 $cmd_pid
}

travis_retry() {
  local result=0
  local count=1
  while [ $count -le 3 ]; do
    [ $result -ne 0 ] && {
      echo -e "\n${ANSI_RED}The command \"$@\" failed. Retrying, $count of 3.${ANSI_RESET}\n" >&2
    }
    "$@"
    result=$?
    [ $result -eq 0 ] && break
    count=$(($count + 1))
    sleep 1
  done

  [ $count -gt 3 ] && {
    echo -e "\n${ANSI_RED}The command \"$@\" failed 3 times.${ANSI_RESET}\n" >&2
  }

  return $result
}

travis_fold() {
  local action=$1
  local name=$2
  echo -en "travis_fold:${action}:${name}\r${ANSI_CLEAR}"
}

decrypt() {
  echo $1 | base64 -d | openssl rsautl -decrypt -inkey ~/.ssh/id_rsa.repo
}

# XXX Forcefully removing rabbitmq source until next build env update
# See http://www.traviscistatus.com/incidents/6xtkpm1zglg3
if [[ -f /etc/apt/sources.list.d/rabbitmq-source.list ]] ; then
  sudo rm -f /etc/apt/sources.list.d/rabbitmq-source.list
fi

mkdir -p $HOME/build
cd       $HOME/build


travis_fold start system_info
  echo -e "\033[33;1mBuild system information\033[0m"
  echo -e "Build language: python"
  echo -e "Build group: stable"
  echo -e "Build dist: precise"
  echo -e "Build id: ''"
  echo -e "Job id: ''"
  if [[ -f /usr/share/travis/system_info ]]; then
    cat /usr/share/travis/system_info
  fi
travis_fold end system_info

echo
export PATH=$(echo $PATH | sed -e 's/::/:/g')
echo "options rotate
options timeout:1

nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 208.67.222.222
nameserver 208.67.220.220
" | sudo tee /etc/resolv.conf &> /dev/null
sudo sed -e 's/^\(127\.0\.0\.1.*\)$/\1 '`hostname`'/' -i'.bak' /etc/hosts
test -f /etc/mavenrc && sudo sed -e 's/M2_HOME=\(.\+\)$/M2_HOME=${M2_HOME:-\1}/' -i'.bak' /etc/mavenrc
if [ $(command -v sw_vers) ]; then
  echo "Fix WWDRCA Certificate"
  sudo security delete-certificate -Z 0950B6CD3D2F37EA246A1AAA20DFAADBD6FE1F75 /Library/Keychains/System.keychain
  wget -q https://developer.apple.com/certificationauthority/AppleWWDRCA.cer
  sudo security add-certificates -k /Library/Keychains/System.keychain AppleWWDRCA.cer
fi

sudo sed -e 's/^127\.0\.0\.1\(.*\) localhost \(.*\)$/127.0.0.1 localhost \1 \2/' -i'.bak' /etc/hosts 2>/dev/null
# apply :home_paths
for path_entry in $HOME/.local/bin $HOME/bin ; do
  if [[ ${PATH%%:*} != $path_entry ]] ; then
    export PATH="$path_entry:$PATH"
  fi
done

if [ ! $(uname|grep Darwin) ]; then echo update_initramfs=no | sudo tee -a /etc/initramfs-tools/update-initramfs.conf > /dev/null; fi
mkdir -p $HOME/.ssh
chmod 0700 $HOME/.ssh
touch $HOME/.ssh/config
echo -e "Host *
  UseRoaming no
" | cat - $HOME/.ssh/config > $HOME/.ssh/config.tmp && mv $HOME/.ssh/config.tmp $HOME/.ssh/config
function travis_debug() {
echo -e "\033[31;1mThe debug environment is not available. Please contact support.\033[0m"
false
}

if [[ ! -f ~/virtualenv/python2.7.10/bin/activate ]]; then
  echo -e "\033[33;1m2.7.10 is not installed; attempting download\033[0m"
  if [[ $(uname) = 'Linux' ]]; then
    travis_host_os=$(lsb_release -is | tr 'A-Z' 'a-z')
    travis_rel_version=$(lsb_release -rs)
  elif [[ $(uname) = 'Darwin' ]]; then
    travis_host_os=osx
    travis_rel=$(sw_vers -productVersion)
    travis_rel_version=${travis_rel%*.*}
  fi
  archive_url=https://s3.amazonaws.com/travis-python-archives/binaries/${travis_host_os}/${travis_rel_version}/$(uname -m)/python-2.7.10.tar.bz2
  travis_cmd curl\ -s\ -o\ python-2.7.10.tar.bz2\ \$\{archive_url\} --assert
  travis_cmd sudo\ tar\ xjf\ python-2.7.10.tar.bz2\ --directory\ / --assert
  rm 2.7.10.tar.bz2
  sed -e 's|export PATH=\(.*\)$|export PATH=/opt/python/2.7.10/bin:\1|' /etc/profile.d/pyenv.sh > /tmp/pyenv.sh
  cat /tmp/pyenv.sh | sudo tee /etc/profile.d/pyenv.sh > /dev/null
fi

export GIT_ASKPASS=echo

travis_fold start git.checkout
  if [[ ! -d dvirtz/pybind11-test/.git ]]; then
    travis_cmd git\ clone\ --depth\=50\ --branch\=\'master\'\ https://github.com/dvirtz/pybind11-test.git\ dvirtz/pybind11-test --assert --echo --retry --timing
  else
    travis_cmd git\ -C\ dvirtz/pybind11-test\ fetch\ origin --assert --echo --retry --timing
    travis_cmd git\ -C\ dvirtz/pybind11-test\ reset\ --hard --assert --echo
  fi
  travis_cmd cd\ dvirtz/pybind11-test --echo
  travis_cmd git\ checkout\ -qf\  --assert --echo
travis_fold end git.checkout

if [[ -f .gitmodules ]]; then
  travis_fold start git.submodule
    echo Host\ github.com'
    '\	StrictHostKeyChecking\ no'
    ' >> ~/.ssh/config
    travis_cmd git\ submodule\ update\ --init\ --recursive --assert --echo --retry --timing
  travis_fold end git.submodule
fi

rm -f ~/.ssh/source_rsa

travis_fold start apt
  echo -e "\033[33;1mAdding APT Sources (BETA)\033[0m"
  # echo -e "\033[31;1mDisallowing sources: george-edison55-precise-backports, ubuntu-toolchain-r-test, deadsnakes\033[0m"
  # echo -e "To add unlisted APT sources, follow instructions in https://docs.travis-ci.com/user/installing-dependencies#Installing-Packages-with-the-APT-Addon"
  # echo -e "\033[33;1mInstalling APT Packages (BETA)\033[0m"
  travis_cmd export\ DEBIAN_FRONTEND\=noninteractive --echo
  travis_cmd sudo\ -E\ apt-add-repository\ -y\ \"ppa:george-edison55/precise-backports\"
  travis_cmd sudo\ -E\ apt-add-repository\ -y\ \"ppa:ubuntu-toolchain-r/test\"
  travis_cmd sudo\ -E\ apt-add-repository\ -y\ \"ppa:fkrull/deadsnakes\"
  travis_cmd sudo\ -E\ apt-get\ -yq\ update\ \&\>\>\ \~/apt-get-update.log --echo --timing
  travis_cmd sudo\ -E\ apt-get\ -yq\ --no-install-suggests\ --no-install-recommends\ --force-yes\ install\ g\+\+-4.9\ gcc-4.9\ libffi-dev\ libssl-dev --echo --timing
  result=$?
  if [[ $result -ne 0 ]]; then
    travis_fold start apt-get.diagnostics
      echo -e "\033[31;1mapt-get install failed\033[0m"
      travis_cmd cat\ \~/apt-get-update.log --echo
    travis_fold end apt-get.diagnostics
    TRAVIS_CMD='sudo -E apt-get -yq --no-install-suggests --no-install-recommends --force-yes install g++-4.9 gcc-4.9 libffi-dev libssl-dev'
    travis_assert $result
  fi
travis_fold end apt

export PS4=+
export TRAVIS=true
export CI=true
export CONTINUOUS_INTEGRATION=true
export HAS_JOSH_K_SEAL_OF_APPROVAL=true
export TRAVIS_EVENT_TYPE=''
export TRAVIS_PULL_REQUEST=false
export TRAVIS_SECURE_ENV_VARS=false
export TRAVIS_BUILD_ID=''
export TRAVIS_BUILD_NUMBER=''
export TRAVIS_BUILD_DIR=$HOME/build/dvirtz/pybind11-test
export TRAVIS_JOB_ID=''
export TRAVIS_JOB_NUMBER=''
export TRAVIS_BRANCH=''
export TRAVIS_COMMIT=''
export TRAVIS_COMMIT_RANGE=''
export TRAVIS_REPO_SLUG=dvirtz/pybind11-test
export TRAVIS_OS_NAME=linux
export TRAVIS_LANGUAGE=python
export TRAVIS_TAG=''
echo
echo -e "\033[33;1mSetting environment variables from .travis.yml\033[0m"
travis_cmd export\ CTEST_OUTPUT_ON_FAILURE\=1 --echo
travis_cmd export\ CXX\=g\+\+ --echo
travis_cmd export\ BUILD_TYPE\=Release --echo
echo
export TRAVIS_PYTHON_VERSION=2.7.10
travis_cmd source\ \~/virtualenv/python2.7.10/bin/activate --assert --echo --timing
travis_cmd python\ --version --echo
travis_cmd pip\ --version --echo
export PIP_DISABLE_PIP_VERSION_CHECK=1

travis_fold start install.1
  travis_cmd if\ \[\ \"\$CXX\"\ \=\ \"g\+\+\"\ \]\;\ then\ export\ CXX\=\"g\+\+-4.9\"\ CC\=\"gcc-4.9\"\;\ fi --assert --echo --timing
travis_fold end install.1

travis_fold start install.2
  travis_cmd if\ \[\ \"\$CXX\"\ \=\ \"clang\+\+\"\ \]\;\ then\ export\ CXX\=\"clang\+\+-3.8\"\ CC\=\"clang-3.8\"\;\ fi --assert --echo --timing
travis_fold end install.2

travis_fold start install.3
  travis_cmd source\ scripts/install-cmake.sh --assert --echo --timing
travis_fold end install.3

travis_fold start install.4
  travis_cmd source\ scripts/install-gmusicapi.sh --assert --echo --timing
travis_fold end install.4

travis_cmd cmake\ .\ -B_build\ -DCMAKE_BUILD_CONFIGURATION\=\$BUILD_TYPE --echo --timing
travis_result $?
travis_cmd cmake\ --build\ _build --echo --timing
travis_result $?
travis_cmd cmake\ --build\ _build\ --target\ test --echo --timing
travis_result $?
echo -e "\nDone. Your build exited with $TRAVIS_TEST_RESULT."

travis_terminate $TRAVIS_TEST_RESULT
