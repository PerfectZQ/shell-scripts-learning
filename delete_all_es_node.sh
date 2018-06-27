jps | grep -i elasticsearch | awk '{print $1}' | xargs kill -9
userdel es 
rm -rf /home/es/ 
rm -rf ~/.ssh/

