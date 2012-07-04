STUF = -m32 -march=native -O2 -lm
all:
	gcc ${STUF} -c -fPIC clc.c -o clc.o
	gcc ${STUF} -shared clc.o -o clc.so
