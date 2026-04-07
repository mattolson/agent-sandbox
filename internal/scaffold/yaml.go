package scaffold

import (
	"bytes"

	"gopkg.in/yaml.v3"
)

func marshalYAML(document any) ([]byte, error) {
	var body bytes.Buffer

	encoder := yaml.NewEncoder(&body)
	encoder.SetIndent(2)
	if err := encoder.Encode(document); err != nil {
		_ = encoder.Close()
		return nil, err
	}
	if err := encoder.Close(); err != nil {
		return nil, err
	}

	return body.Bytes(), nil
}
