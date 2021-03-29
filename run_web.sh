
PORT=4001 \
    NETWORK=Celo \
    ETHEREUM_JSONRPC_VARIANT=geth \
    ETHEREUM_JSONRPC_HTTP_URL=http://localhost:8545 \
    ETHEREUM_JSONRPC_WS_URL=ws://localhost:8546 \
    COIN=CELO \
    DATABASE_URL=postgresql://postgres:1234@localhost:5432/blockscout \
    mix cmd --app block_scout_web "mix phx.server"