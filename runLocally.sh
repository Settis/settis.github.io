#!/bin/bash

GEM_HOME="$(ruby -e 'puts Gem.user_dir')"
PATH="$PATH:$GEM_HOME/bin"
jekyll s --draft --config _config.yml,_config_local.yml -H 0.0.0.0 -l
