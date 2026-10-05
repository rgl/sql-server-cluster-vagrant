all: diagram.png 

diagram.png: diagram.uxf
	umlet \
		-action=convert \
		-format=png \
		-filename=$< \
		-output=$@.tmp
	pngquant --ext .png --strip --force $@.tmp.png
	mv $@.tmp.png $@

.PHONY: all
