# friac
Fast Redis Installer and Configurator with Twemproxy Support

Used to setup Redis 4.0, configure multiple instances in systemd, and setup twemproxy with a systemd service.

Meant to be used in Ubuntu on Digital Ocean. Private networking should be enabled if you plan to bind to the private ip.

# Installation

```
wget https://raw.githubusercontent.com/tmyers273/friac/master/redis.sh
chmod +x redis.sh
./redis.sh
```

# Todo

- Add default `hash_tag` field to nutcracker.yml
- Fix package installation check
