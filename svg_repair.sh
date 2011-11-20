#!/bin/bash

cat fgtw01-tutorial.svg | sed -e "s:</svg>:</g></g></svg>:" > ok.svg && cat
fgtw01-tutorial.png > ok.png
