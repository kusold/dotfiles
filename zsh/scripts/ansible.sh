#!/usr/bin/env zsh
autoload command_exists

if command_exists ansible-playbook; then
  alias vagrant-ansible-playbook='ansible-playbook -i .vagrant/provisioners/ansible/inventory/vagrant_ansible_inventory --private-key=.vagrant/machines/default/virtualbox/private_key -u vagrant'
fi
