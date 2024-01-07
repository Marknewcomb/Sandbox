#!/bin/bash

# Bash Testing

echo 'Bash Testing'

touch 'sample.txt'
read -p 'What contact would you like to add? (First,Last,Force Affiliation,Power Level,Home Planet)' contact
echo "${contact}" >> sample.txt
cat sample.txt

bash
