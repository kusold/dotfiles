#!/usr/bin/env zsh

alias btc='echo "Btc(usd): $"$(curl -sL https://api.coinmarketcap.com/v1/ticker/bitcoin/ | jq ".[0].price_usd" | cut -d\" -f2 )'
alias eth='echo "Eth(usd): $"$(curl -sL https://api.coinmarketcap.com/v1/ticker/ethereum/ | jq ".[0].price_usd" | cut -d\" -f2 )'
