run:        ## run the server
	shards run
spec:       ## run tests
	crystal spec --error-trace
fmt:        ## format
	crystal tool format
build:      ## build release binary
	shards build --release
help:       ## this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
