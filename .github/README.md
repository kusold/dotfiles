# Dotfiles

## Install
```
curl -fLo ~/bin/yadm https://github.com/TheLocehiliosan/yadm/raw/master/yadm && chmod a+x ~/bin/yadm
yadm clone git@github.com:kusold/dotfiles.git
yadm bootstrap
yadm decrypt
```

## Terminal Colors
I use the excellent [base16](https://github.com/chriskempson/base16) package for colors. My favorite theme is [eighties](http://chriskempson.github.io/base16/#eighties)

## Someday:
* Remove nodenv, rbenv, etc... and manage versions with asdf
