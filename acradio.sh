#!/bin/bash

RAIN_SOCK="/tmp/acradio_rain_sock"
PLAYER_SOCK="/tmp/acradio_sock"

ENABLE_RAIN=0
ENABLE_MUSIC=1
AUTO_RAIN=0
AUTO_RAIN_LOC=""

RAIN_STATE=0
MUSIC_STATE=0
LOCATION_RAIN_STATE=0

RAIN_VOLUME=50
MUSIC_VOLUME=100

EXIT_RCPT=false

GAME="new_horizons"
CONTROL_FILE=/tmp/acbgm_ctrl

SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )

CONFIG_FILE="$HOME/.config/acradio"

bold=$(tput bold)
normal=$(tput sgr0)

joinBy() {
  local d=${1-} f=${2-}
  if shift 2; then
    printf %s "$f" "${@/#/$d}"
  fi
}

ipcCmd() {
  cmdStr="[\""
  argStr="$(joinBy '", "' "${@}")"
  cmdStr+="$argStr"
  cmdStr+="\"]"

  cat << EOF
{ "command": $cmdStr }
EOF
}

getSock() {
  case $1 in
    music)
      echo "$PLAYER_SOCK"
      ;;
    rain)
      echo "$RAIN_SOCK"
      ;;
    *)
      echo ""
      ;;
  esac
}

cleanup() {
  controlSock="$(getSock $1)"

  ipcCmd quit 0 | socat - $controlSock
}

exitCleanup() {
  cleanup music &> /dev/null
  cleanup rain &> /dev/null
  rm $PLAYER_SOCK
  rm $RAIN_SOCK
  rm $CONTROL_FILE
  EXIT_RCPT=true
  exit 0
}

getHour() {
  date '+%H'
}

getRain() {
  if wttr="$(curl wttr.in/"$AUTO_RAIN_LOC"?format="%C" 2>/dev/null)"; then
    if [ "$(echo "$wttr" | grep -i rain)" != "" ]; then
      echo 1
    fi
  else
    echo 0
  fi
}

playMusic() {
  mpv --loop --volume="$MUSIC_VOLUME" --input-ipc-server="$PLAYER_SOCK" --no-terminal "$DIR/$GAME/$1.mp3" &
}

playRain() {
  mpv --loop --volume="$RAIN_VOLUME" --input-ipc-server="$RAIN_SOCK" --no-terminal "$DIR/ambient/rain.mp3" &
}

volumeUp() {
  controlSock="$(getSock $1)"
  ipcCmd add volume 2 | socat - $controlSock &> /dev/null
  getVolume "$1"
}

volumeDown() {
  controlSock="$(getSock $1)"
  ipcCmd add volume -2 | socat - $controlSock &> /dev/null
  getVolume "$1"
}

getVolume() {
  controlSock="$(getSock $1)"
  res="$(ipcCmd get_property_string volume | socat - $controlSock)"
  echo "$res" | grep -Po '\d+(?=\.)'
}

setVolume() {
  controlSock="$(getSock $1)"
  echo "$controlSock"
  ipcCmd set volume $2 | socat - $controlSock &> /dev/null
  getVolume "$1"
}

toggleRain() {
  if [ -f $CONTROL_FILE ]; then
    . $CONTROL_FILE
  fi

  if [ "$AUTO_RAIN" -eq 1 ]; then
    AUTO_RAIN=0
  fi

  ENABLE_RAIN=$((1 - ENABLE_RAIN))

  if [[ "$ENABLE_RAIN" != "$RAIN_STATE" ]]; then
    if [ "$RAIN_STATE" -eq 1 ]; then
      cleanup rain &> /dev/null
    elif [ "$RAIN_STATE" -eq 0 ]; then
      playRain &> /dev/null &
    fi
    RAIN_STATE=$((1 - RAIN_STATE))
  fi

  writeStates
}

toggleMusic() {
  if [ -f $CONTROL_FILE ]; then
    . $CONTROL_FILE
  fi

  current_hour="$(getHour)"
  ENABLE_MUSIC=$((1 - ENABLE_MUSIC))

  if [[ "$ENABLE_MUSIC" != "$MUSIC_STATE" ]]; then
    if [ "$MUSIC_STATE" -eq 1 ]; then
      cleanup music &> /dev/null
    elif [ "$MUSIC_STATE" -eq 0 ]; then
      playMusic "$current_hour" &> /dev/null &
      PLAYING_HOUR="$current_hour"
    fi
    MUSIC_STATE=$((1 - MUSIC_STATE))
  fi

  writeStates
}

writeStatesInternal() {
  cat <<EOF
ENABLE_RAIN=$ENABLE_RAIN
ENABLE_MUSIC=$ENABLE_MUSIC
RAIN_STATE=$RAIN_STATE
MUSIC_STATE=$MUSIC_STATE
PLAYING_HOUR=$PLAYING_HOUR
LOCATION_RAIN_STATE=$LOCATION_RAIN_STATE
EOF
}

writeStates() {
  writeStatesInternal > $CONTROL_FILE
}

rainStateUpdater() {
  while true 
  do
    LOCATION_RAIN_STATE=$(getRain)
    sleep 5m
  done
}

volumeHandler() {
  cmd=""
  player="music"
  case $1 in
    up)
      cmd="up"
      ;;
    down)
      cmd="down"
      ;;
    get | "")
      cmd="get"
      ;;
    set)
      cmd="set"
      ;;
    rain)
      cmd="get"
      player="rain"
      ;;
    music)
      cmd="get"
      player="music"
      ;;
    *)
      echo "unknown argument: $1. Valid subcommands are 'up', 'down', 'set', or 'get'"
      exit 1
      ;;
  esac
  shift 1
  
  volume=0

  if [[ "$#" -gt 2 ]]; then
    echo "Too many arguments provided!"
    showHelp
    exit 1
  fi

  for arg in "$@"; do
    if [ "$arg" == "rain" ]; then
      player=rain
      continue
    elif [ "$arg" == "music" ]; then
      continue
    elif [[ $arg =~ ^[0-9]+$ ]]; then
      volume=$arg
      if [[ $arg -gt 100 ]]; then
        volume=100
      elif [[ $arg -lt 0 ]]; then
        volume=0
      fi
    fi
  done 

  if [ "$player" == "rain" ] && [ $RAIN_STATE -eq 0 ]; then
    echo "OFF"
    exit 0
  fi

  if [ "$player" == "music" ] && [ $MUSIC_STATE -eq 0 ]; then
    echo "OFF"
    exit 0
  fi

  if [ "$cmd" == "up" ]; then
    volumeUp $player
  elif [ "$cmd" == "down" ]; then
    volumeDown $player
  elif [ "$cmd" == "get" ]; then
    getVolume $player
  elif [ "$cmd" == "set" ]; then
    setVolume "$player" "$volume"
  fi
}

showHelp() {
  echo "${bold}Usage:${normal} acradio [ command [ subcommand [ options ] | options ] ]"
  echo ""
  echo "${bold}Commands${normal}"
  printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' - | cut -c -80
  echo "  ${bold}play${normal} - start ACRadio player [default]"
  echo ""
  echo "  ${bold}toggle${normal} - toggle the playing state of the rain or music player"
  echo "    options - rain, music, all [default: all]"
  echo ""
  echo "  ${bold}volume${normal} - adjust the volume of the specified player. If the player is not"
  echo "           specified, the subcommand given applies to the music player."
  echo "    usage: acradio volume [ subcommand ] [ player ] [ value ]"
  echo "    example: acradio volume set music 100"
  echo ""
  echo "    ${bold}subcommands${normal}"
  echo "      up   - increase the volume of the specified player by 2%"
  echo "      down - decrease the volume of the specified player by 2%"
  echo "      set  - set the volume of the specified player to the given value [0-100]"
  echo "      get  - get the volume of the specified player"
  echo ""
  echo "  ${bold}help${normal} - print this help message"
}

playHandler() {
  trap exitCleanup ERR EXIT
  
  current_hour="$(getHour)"

  if [ -f $CONFIG_FILE ]; then
    . $CONFIG_FILE
  fi

  if [ "$ENABLE_MUSIC" -eq 1 ] && [ "$MUSIC_STATE" -eq 0 ]; then
    playMusic "$current_hour" &> /dev/null &
    MUSIC_STATE=1
    PLAYING_HOUR="$current_hour"
  fi

  if [ "$RAIN_STATE" -eq 0 ]; then
    if [ "$AUTO_RAIN" -eq 1 ] && [ "$ENABLE_RAIN" -eq 0 ]; then
      rainStateUpdater &
    fi

    if [ "$AUTO_RAIN" -eq 1 ] && [ "$LOCATION_RAIN_STATE" -eq 1 ]; then
      playRain &> /dev/null &
      RAIN_STATE=1
    elif [ "$ENABLE_RAIN" -eq 1 ]; then
      playRain &> /dev/null
      RAIN_STATE=1
    fi
  fi
  writeStates

  

  while true
  do
    current_hour="$(getHour)"

    . $CONTROL_FILE
  
    if [[ "$current_hour" != "$PLAYING_HOUR" ]] && [ "$MUSIC_STATE" -eq 1 ]; then
      cleanup music &> /dev/null &
      playMusic "$current_hour" &> /dev/null &
      PLAYING_HOUR="$current_hour"
      writeStates
    fi

    if [ "$EXIT_RCPT" = true ]; then
      break
    fi

    sleep 1
  done
  exit 0
}

toggleHandler() {
  case $1 in
    music)
      toggleMusic
      ;;
    rain)
      toggleRain
      ;;
    all | "")
      toggleMusic
      if [ "$RAIN_STATE" -eq "$MUSIC_STATE" ]; then
        toggleRain
      fi
      ;;
    *)
      echo "unknown argument: $1, valid arguments are 'music', 'rain', or 'all'"
      exit 1
      ;;
  esac
  exit 0
}

main() {
  if [ -f $CONFIG_FILE ]; then
    . $CONFIG_FILE
  fi  

  if [ -f $CONTROL_FILE ]; then
    . $CONTROL_FILE
  else
    touch $CONTROL_FILE
  fi


  if [ "$1" == "" ]; then
    playHandler
  else
    case $1 in 
      play)
        shift 1
        playHandler "$@"
        ;;
      toggle)
        shift 1
        toggleHandler "$@"
        ;;
      volume)
        shift 1
        volumeHandler "$@"
        ;;
      help)
        showHelp
        exit 0
        ;;
      *)
        showHelp
        exit 1
        ;;
    esac
  fi
}

main "$@"
