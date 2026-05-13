//go:build !linux && !darwin && !freebsd && !openbsd && !netbsd

package agent

func defaultDiskFreeBytes(path string) (uint64, error) {
	return 1 << 40, nil
}
