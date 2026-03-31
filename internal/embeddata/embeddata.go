package embeddata

import (
	"embed"
	"io/fs"
	"path"
	"strings"
)

//go:generate ../../scripts/sync-go-templates.bash

//go:embed templates/**
var embeddedFiles embed.FS

func TemplatesFS() fs.FS {
	subtree, err := fs.Sub(embeddedFiles, "templates")
	if err != nil {
		panic(err)
	}

	return subtree
}

func ReadTemplate(name string) ([]byte, error) {
	clean := path.Clean(strings.TrimPrefix(name, "/"))
	return fs.ReadFile(TemplatesFS(), clean)
}
