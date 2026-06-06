#!/bin/bash
#
#                         License
#
#=================================================
# Copyright (C) June 4, 2026  David Valin dvalin@redhat.com
#=================================================
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# This script automates the execution of coremark.  It will determine the
# set of default run parameters based on the system configuration.
#

#=================================================
valkey_version="v1.00"
version=1.00
test_name=valkey
#=================================================
results_file="results_${test_name}.csv"
arguments="$@"
script_dir=$(realpath $(dirname $0))
pcpdir=""

#total_requests=600000
total_requests=100000
connections=50
threads=""

exit_out()
{
	echo $1
	exit $2
}

if [ ! -f "/tmp/${test_name}.out" ]; then
	command="${0} $@"
	echo $command
	$command &> /tmp/${test_name}.out
	rtc=$?
	cat /tmp/${test_name}.out
	rm /tmp/${test_name}.out
	exit $rtc 
fi

curdir=$(dirname $(realpath $0))
if [[ $0 == "./"* ]]; then
	chars=`echo $0 | awk -v RS='/' 'END{print NR-1}'`
	if [[ $chars == 1 ]]; then
		run_dir=`pwd`
	else
		run_dir=`echo $0 | cut -d'/' -f 1-${chars} | cut -d'.' -f2-`
		run_dir="${curdir}${run_dir}"
	fi
elif [[ $0 != "/"* ]]; then
	dir=`echo $0 | rev | cut -d'/' -f2- | rev`
	run_dir="${curdir}/${dir}"
else
	chars=`echo $0 | awk -v RS='/' 'END{print NR-1}'`
	run_dir=`echo $0 | cut -d'/' -f 1-${chars}`
	if [[ $run_dir != "/"* ]]; then
		run_dir=${curdir}/${run_dir}
	fi
fi
cd $run_dir

show_usage=0

TOOLS_BIN="$HOME/test_tools"
export TOOLS_BIN

usage()
{
	echo "Usage $1:"
	echo add usage
	source $TOOLS_BIN/general_setup --usage
	exit $E_USAGE
}


attempt_tools_generic()
{
	method="$1"
        if [[ ! -d "$TOOLS_BIN" ]]; then
               $method ${tools_git}/archive/refs/heads/main.zip
                if [[ $? -eq 0 ]]; then
                        unzip -q main.zip
                        mv test_tools-wrappers-main ${TOOLS_BIN}
                        rm main.zip
                fi
        fi
}

attempt_tools_git()
{
        if [[ ! -d "$TOOLS_BIN" ]]; then
                git clone $tools_git "$TOOLS_BIN"
                if [ $? -ne 0 ]; then
                        exit_out "Error: pulling git $tools_git failed." 101
                fi
        fi
}

install_test_tools()
{
	#
	# Clone the repo that contains the common code and tools
	#
	tools_git=https://github.com/redhat-performance/test_tools-wrappers
	found=0
	for arg in "$@"; do
		if [ $found -eq 1 ]; then
			tools_git=$arg
			found=0
		fi
		if [[ $arg == "--tools_git" ]]; then
			found=1
		fi

		#
		# We do the usage check here, as we do not want to be calling
		# the common parsers then checking for usage here.  Doing so will
		# result in the script exiting with out giving the test options.
		#
		if [[ $arg == "--usage" ]]; then
			show_usage=1
		fi
	done

	#
	# Check to see if the test tools directory exists.  If it does, we do not need to
	# clone the repo.
	#
	attempt_tools_generic "wget"
	attempt_tools_generic "curl -L -O "
	attempt_tools_git

	if [ $show_usage -eq 1 ]; then
		usage $1
	fi
}

install_test_tools "$@"

#
# Variables set by general setup.
#
# TOOLS_BIN: points to the tool directory
# to_home_root: home directory
# to_configuration: configuration information
# to_times_to_run: number of times to run the test
# to_run_label: Label for the run
# to_user: User on the test system running the test
# to_sys_type: for results info, basically aws, azure or local
# to_sysname: name of the system
# to_tuned_setting: tuned setting
#

pushd $curdir 2> /dev/null
source "$TOOLS_BIN/general_setup" "$@"
popd 2> /dev/null
# Gather hardware information
$TOOLS_BIN/gather_data ${curdir}
test_list=""

execute_valkey()
{
	out_file=valkey_iter_${1}
	test_list=""


	run_threads=$(echo $threads | sed "s/,/ /g")
	run_threads=1
	for th in $run_threads;
	do
		if [[ $to_use_pcp -eq 1 ]]; then
			start_pcp_subset
		fi
		start_time=$(retrieve_time_stamp)
		valkey-benchmark -h 127.0.0.1 -p 6379 -n $total_requests -c $connections  --threads $th --csv  | sed "s/\"//g" | sed "s/ /_/g" | sed "s/)//g" | sed "s/(//g" > ${out_file}_${th}_threads.csv
		end_time=$(retrieve_time_stamp)
		if [[ $test_list == "" ]]; then
			separ=""
			echo file "${out_file}_${th}_threads.csv"
			while IFS= read -r run_data
			do
				if [[ $run_data == *"test"* ]]; then
					continue
				fi
				tst=$(echo $run_data | cut -d, -f 1 | sed "s/\"//g" | sed "s/ /_/g"| sed "s/)//g")
				test_list=${tst}${separ}${test_list}
				separ=' '
			done < "${out_file}_${th}_threads.csv"
		fi
		if [[ $to_use_pcp -eq 1 ]]; then
			results2pcp_add_value "iteration:${1}"
			results2pcp_add_value "runlog:1"
			results2pcp_add_value "numthreads:$th"
			results2pcp_add_value "IterationsPerSec:0"
			#
			# Record the values for this thread.
			#
			for tst in $test_list
			do
				value=$(grep "^${tst}", ${out_file}_${th}_threads.csv  | cut -d',' -f2 | sed "s/\"//g" | cut -d'.' -f 1 )
				results2pcp_add_value "${tst}:${value}"
			done
			results2pcp_add_value_commit
			reset_pcp_om
			stop_pcp_subset
		fi
	done

	$TOOLS_BIN/test_header_info --front_matter --results_file ${out_file}.csv --host $to_configuration --sys_type $to_sys_type --tuned $to_tuned_setting --results_version $valkey_version --test_name $test_name --field_header "Test,RPS"
	for tst in $test_list
	do
		value=$(grep "^$tst", *csv | cut -d',' -f2 | sed "s/\"//g" | sort -n | tail -1)
		echo ${tst},${value},${start_time},${end_time} >> ${out_file}.csv
	done
	pwd
	echo ${TOOLS_BIN}/csv_to_json $to_json_flags --csv_file ${out_file}.csv --output_file valkey_verify.json
	${TOOLS_BIN}/csv_to_json $to_json_flags --csv_file ${out_file}.csv --output_file valkey_verify.json
	test_rtc=$?
	if [[ $test_rtc -ne 0 ]]; then
		exit_out "${TOOLS_BIN}/csv_to_json $to_json_flags --csv_file ${out_file}.csv --output_file valkey_verify.json returned an an error" $test_rtc
	fi
	${TOOLS_BIN}/verify_results $to_verify_flags --schema_file $script_dir/results_schema.py --class_name valkey_Results --file valkey_verify.json
	test_rtc=$?
	if [[ $test_rtc -ne 0 ]]; then
		echo Test failure detected: $out_File
	fi
}

ARGUMENT_LIST=(
	"commit"
	"connections"
	"threads"
	"total_requests"
)

NO_ARGUMENTS=(
	"usage"
)

# read arguments
opts=$(getopt \
	--longoptions "$(printf "%s:," "${ARGUMENT_LIST[@]}")" \
	--longoptions "$(printf "%s," "${NO_ARGUMENTS[@]}")" \
	--name "$(basename "$0")" \
	--options "h" \
	-- "$@"
)

eval set --$opts

while [[ $# -gt 0 ]]; do
	case "$1" in
		--commit)
			commit=$2
			shift 2
		;;
		--connections)
			connections=$2
			shift 2
		;;
		--threads)
			threads=$2
			shift 2
		;;
		--total_requests)
			total_requests=$2
			shift 2
		;;
		--usage)
			usage $0
		;;
		-h)
			usage $0
		;;
		--)
			break
		;;
		*)
			echo option not found $1
			usage $0
		;;
	esac
done

if [[ $threads == "" ]]; then
	cpus=$(nproc)
	if [[ $cpus -lt 8 ]]; then
		intervals=$cpus
	else
		intervals=8
	fi
	threads=$(${TOOLS_BIN}/generate_intervals --interval $intervals --max_value $cpus)
fi

package_tool --no_packages $to_no_pkg_install --wrapper_config $curdir/../valkey.json

# Get PCP setup if we're using it
if [[ $to_use_pcp -eq 1 ]]; then
	source $TOOLS_BIN/pcp/pcp_commands.inc
	setup_pcp
	pcp_cfg=$TOOLS_BIN/pcp/default.cfg
	pcpdir=/tmp/pcp_`date "+%Y.%m.%d-%H.%M.%S"`
	echo "Start PCP"
	echo start_pcp ${pcpdir}/ ${test_name} $pcp_cfg
	start_pcp ${pcpdir}/ ${test_name} $pcp_cfg
	echo returned from start_pcp
fi

rm -rf *csv
for iter in $(seq 1 1 $to_times_to_run); do
	execute_valkey $iter
done

# Shutdown PCP and clean up after ourselves
if [[ $to_use_pcp -eq 1 ]]; then
        shutdown_pcp
fi
#$TOOLS_BIN/csv_to_json $to_json_flags --csv_file ${results_file} --output_file results_<test_name>.json
#$TOOLS_BIN/verify_results $to_verify_flags --schema_file $script_dir/../result_schema.py --class_name <classname> --file results_<test_name>.json


#${TOOLS_BIN}/save_results --curdir $curdir --home_root $to_home_root <arguments>

#example

#${TOOLS_BIN}/save_results --curdir $curdir --home_root $to_home_root <arguments> --other_files "*_summary,run*log,test_results_report,${pcpdir}" --results $results_file --test_name coremark --tuned_setting=$to_tuned_setting --version $<test_name>_version --user $to_user
#=================================================
exit $E_SUCCESS
