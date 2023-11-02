# Dotfiles

## Install
```
curl --fail --silent --output ~/bootstrap https://raw.githubusercontent.com/kusold/dotfiles/master/bin/bootstrap && bash ~/bootstrap &&& rm ~/bootstrap
```

## Terminal Colors
I use the excellent [base16](https://github.com/chriskempson/base16) package for colors. My favorite theme is [eighties](http://chriskempson.github.io/base16/#eighties)

## Someday:
* Remove nodenv, rbenv, etc... and manage versions with asdf

# Applications
## Firefox
### Enable U2F
Go to `about:config`, set `security.webauth.u2f` to `true`

[Reference](https://www.yubico.com/2017/11/how-to-navigate-fido-u2f-in-firefox-quantum/)
## MacOS
### Key remap
Settings -> Keyboard -> Modifier Keys
Remap caps lock to escape.
### Send text messages through iMessage
[Reference](https://support.apple.com/guide/messages/set-up-to-send-text-messages-ichte16154fb/12.0/mac/10.14)
## iTerm2
### enable clipboard access for tmux
Preferences -> enable Applications in terminal may access clipboard

### Input Icon
Settings -> Keyboard -> Input Sources
Uncheck `Show input menu in menu bar`

