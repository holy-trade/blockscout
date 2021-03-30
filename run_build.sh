#!/bin/bash

rm ./_build -r -f
# rm ./deps -r -f
# rm ./apps/block_scout_web/assets/node_modules -r -f
# rm ./apps/explorer/node_modules -r -f
rm ./logs/dev -r -f

mix local.hex --force
mix local.rebar --force
mix deps.get

cd apps/block_scout_web/assets/ && \
  npm install && \
  npm run build && \
  npm rebuild node-sass && \
  cd -

cd apps/explorer/ && \
  npm install && \
  cd -

# cd deps/libsecp256k1 && \
#   make && \
#   cd -

mix compile