package main

import (
	"io"
	"os"

	"github.com/PurpleSec/escape"
)

func main() {
	buf, err := io.ReadAll(os.Stdin)
	if err != nil {
		panic(err)
	}
	_, err = os.Stdout.WriteString(escape.JSON(string(buf)))
	if err != nil {
		panic(err)
	}
}
