# buildkite-agent Heroku app


## Upgrading the agent

* Clone/update the latest https://github.com/buildkite/agent
* Make sure you've got all the dependencies: `go get`
* Build latest binary for Ubuntu: `env GOOS=linux GOARCH=amd64 go build main.go`
* Copy binary to `bin/buildkite-agent`
