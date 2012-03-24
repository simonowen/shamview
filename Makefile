NAME=shamview

.PHONY: clean

$(NAME).dsk: $(NAME).asm
	pyz80.py -I samdos2 --exportfile=$(NAME).sym $(NAME).asm

clean:
	rm -f $(NAME).dsk $(NAME).sym
