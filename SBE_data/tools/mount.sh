#!/bin/bash
#
# Dependencies:
# - cryptsetup

# Script location
cd $(dirname $0)
source lib/*

# SBE directory
cd ..
sdir="$PWD/"

get_project_name () {

  echo; echo "Existing projects"; echo "-----------"
  for project in *
  do
    if [ -f ${project}/server.config ] && [[ $project != "tools" ]]; then
      echo $project
    fi
  done

  echo; read -p "Which project will you mount? " project

  sdir="${sdir}${project}/"

}

# MAIN



if [[ $@ =~ "--umount" ]]; then

  get_project_name
  umount_backup_directory

elif [[ $@ =~ "--mount" ]]; then

  get_project_name
  mount_backup_directory

else
  echo "Please use flag --mount or --umount"
  exit 1
fi


exit 0
