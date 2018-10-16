if [ ! -d "$HOME/.config" ]; then
	mkdir -p $HOME/.config
fi
export XDG_CONFIG_HOME=$HOME/.config

if [ ! -d "$HOME/.cache" ]; then
	mkdir -p $HOME/.cache
fi
export XDG_CACHE_HOME=$HOME/.cache

if [ ! -d "$HOME/.local/share" ]; then
	mkdir -p $HOME/.local/share
fi
export XDG_DATA_HOME=$HOME/.local/share

# Force applications to adopt XDG
export WAKATIME_HOME=$HOME/.config/wakatime

