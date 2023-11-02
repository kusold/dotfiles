#!/usr/bin/env zsh
autoload command_exists

if command_exists jenv; then
  export PATH="$HOME/.jenv/bin:$PATH"
  eval "$(jenv init -)"
fi

if command_exists java; then
	export JAVA_8_HOME=$(/usr/libexec/java_home -v 1.8)
	alias java8='export JAVA_HOME=$JAVA_8_HOME'


	export JAVA_11_HOME='/opt/marqeta/share/horizon/languages/java/adoptopenjdk/hotspot-11.0.6+10'
	alias java11='export JAVA_HOME=$JAVA_11_HOME'

	# set default
	export JAVA_HOME=$JAVA_11_HOME
fi

# Change gradle home from ~/.gradle
export GRADLE_USER_HOME="$XDG_DATA_HOME"/gradle

