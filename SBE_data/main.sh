#!/bin/bash

cd $(dirname $0)
hdir="$PWD/"

[[ "$@" =~ "--logs" ]] && logs=1 ||  logs=0

# # #
# Update scripts
function getlatest() {
    echo "Getting latest version"
    git pull &>/dev/null
    bash ${hdir}tools/update_scripts.sh
}

if [[ $1 == "update" ]]; then
    getlatest
    exit 0
fi

# # #
# Program
while :
do

  # # #
  # Parse config
  if [ -f ${hdir}config ]; then
      source ${hdir}config
  else
      source ${hdir}tools/config_example
  fi


  # # #
  # Parse backup.xml
  if [ -f ${hdir}backup.xml ]; then

  	b_dirs=($($grep -oP '(?<=<backupdirectory>).*?(?=</backupdirectory>)' ${hdir}backup.xml))
  	b_invs=($($grep -oP '(?<=<intervall>).*?(?=</intervall>)' ${hdir}backup.xml))
  	b_dats=($($grep -oP '(?<=<date>).*?(?=</date>)' ${hdir}backup.xml))
  	b_type=($($grep -oP '(?<=<type>).*?(?=</type>)' ${hdir}backup.xml))

  else

  	message="backup.xml does not exist"
  	echo $message; echo -e "Subject: $message\n\nNew message from SBE\nDir: $hdir\nb_invs: ${b_invs[@]}" | $sendmail $mail
    cp ${hdir}tools/backup.xml-example ${hdir}backup.xml
    echo "Please configure your backup.xml file first"

  fi


  # # #
  # Start backups
  for (( x=0; x < ${#b_dirs[@]}; x++ ))
  do

    if [[ $1 == "now" ]]; then

      dobackup[0]=1
      dobackup[1]=1
      dobackup[2]=1

    else

      dobackup[0]=0	# Triggers backup
      dobackup[1]=0	# Triggers backup
      dobackup[2]=0	# Checks if there are minutes hours or nothing

      # Check intervalls, Possible things
      # 9h
      # 15h
      # 9m
      # 15m
      # 12:13

      # Hours as single digit number
      if [[ "${b_invs[$x]}" =~ ^[0-9][hH]$ ]]; then
        b_invs[x]="$(sed 's/[hH]//g' <<< ${b_invs[$x]})"
        b_date=$(date +"%H")
        dobackup[2]=1

      # Hours as number with to digits
      elif [[ "${b_invs[$x]}" =~ ^[0-9][0-9][hH]$ ]]; then
        b_invs[x]=$(sed 's/[hH]//g' <<< ${b_invs[$x]})
        b_date=$(date +"%H")
        dobackup[2]=1

      # Minutes as single digit number
      elif [[ "${b_invs[$x]}" =~ ^[0-9][0-9][mM]$ ]]; then
        b_invs[x]=$(sed 's/[mM]//g' <<< ${b_invs[$x]})
        b_date=$(date +"%M")
        dobackup[2]=2

      # Minutes as number with to digits
      elif [[ "${b_invs[$x]}" =~ ^[0-9][mM]$ ]]; then
        b_invs[x]="$(sed 's/[mM]//g' <<< ${b_invs[$x]})"
        b_date=$(date +"%M")
        dobackup[2]=2

      # Clock
      elif [[ "${b_invs[$x]}" =~ ^[0-9][0-9]":"[0-9][0-9]$ ]]; then
        b_date=$(date +"%H:%M")
        dobackup[2]=3

      else
        echo "Unknown configuration: ${b_invs[$x]}"
        exit 1
      fi

      # Remove leading zero
      b_date_cleaned=$( sed 's/^0//g'  <<< $b_date)


      # Check modulo on hourly intervalls
      if [ ${dobackup[2]} -eq 1 ] && (( $b_date_cleaned % ${b_invs[$x]} == 0 )); then

        if [[ $(date +"%M") == "00" ]]; then
          dobackup[0]=1
        fi

      # Check modulo on minutely intervalls
      elif [ ${dobackup[2]} -eq 2 ] && (( $b_date_cleaned % ${b_invs[$x]} == 0 )); then

        dobackup[0]=1

      # Simple string comparison for time
      elif [[ "${b_invs[$x]}" =~ "$b_date" ]]; then
        dobackup[0]=1

      else
        [ $logs -eq 1 ] && echo "Not valid ${b_invs[$x]} =~ $b_date"

      fi

      # Check days, Possible things
      # Monday
      # Monday,Tuesday
      # Mo
      # Mo,We,Fr
      # 22

      # If day is represented as 2 digit number
      if [[ "${b_dats[$x]}" =~ ^[0-9][0-9]$ ]]; then
        b_dat=$(date +"%m")
      elif [[ "${b_dats[$x]}" =~ ^[0-9]$ ]]; then
        b_dats[x]="0${b_dats[$x]}"
        b_dat=$(date +"%m")
      elif [[ "${b_dats[$x]}" =~ ^[A-Z][a-z][a-z][a-z][a-z]* ]]; then
        b_dat=$(date +"%A")
      elif [[ "${b_dats[$x]}" =~ ^[A-Z][a-z][a-z]$ ]]; then
        b_dat=$(date +"%a")
      elif [[ "${b_dats[$x]}" =~ ^[A-Z][a-z][a-z]","* ]]; then
        b_dat=$(date +"%a")
      else
        echo "Unknown configuration: ${b_dats[$x]}"
        exit 1
      fi

      if [[ "${b_dats[$x]}" =~ "$b_dat" ]]; then
        dobackup[1]=1
      else
        [ $logs -eq 1 ] && echo "Not valid ${b_dats[$x]} =~ $b_dat"
      fi

    fi

    if [ ${dobackup[0]} -eq 1 ] && [ ${dobackup[1]} -eq 1 ]; then


      if [ -f ${hdir}${b_dirs[$x]}/backup_server.sh ]; then

        echo "Backup ${b_dirs[$x]}"
        bash "${hdir}${b_dirs[$x]}/backup_server.sh" "--${b_type[$x]}" &
        message="Backup for ${b_dirs[$x]} under way..."

      else

        message="Backup directory (${b_dirs[$x]}) doesn't exist"
        echo $message; echo -e "Subject: $message\n\nNew message from SBE" | $sendmail $mail

      fi


    fi
  done

  # Wait for a minute is absolute necessary
  sleep 60

done

exit 0
