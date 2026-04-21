Add a bird to the blocklist and update the Pi.

1. Append the bird name (properly capitalized) to `config/blocklist.txt`
2. Commit with message "Add $BIRD to blocklist" and push
3. Copy the updated blocklist to the Pi: `scp config/blocklist.txt sam@192.168.1.97:~/bird-listener/config/blocklist.txt`

The bird name to add is: $ARGUMENTS
