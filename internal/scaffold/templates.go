package scaffold

import (
	"io/fs"

	"github.com/mattolson/agent-sandbox/internal/embeddata"
)

func TemplatesFS() fs.FS {
	return embeddata.TemplatesFS()
}

func ReadTemplate(name string) ([]byte, error) {
	return embeddata.ReadTemplate(name)
}
