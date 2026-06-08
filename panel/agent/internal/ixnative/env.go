package ixnative

import "os"

func init() {
	getenv = os.Getenv
}
