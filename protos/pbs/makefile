SOURCE_FILES := $(shell ls ../*.proto)
TARGET_FILES := $(SOURCE_FILES:../%.proto=%.pb)

.PHONY: all pbs

all: pbs

pbs: $(TARGET_FILES)

%.pb: ../%.proto
	protoc --proto_path="../" -o$@ $<

clean:
	-rm -rf *.pb
