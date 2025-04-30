# docker-ms-orch-topology
Docker compose file for creating a 1 master - 2 slaves mysql 8 setup with orchestrator and percona toolkit

Usage:

Clone the repo then run:

```
shell> ./build.sh up
```

This will start the master node, the two slaves, the orchestrator and a side container with percona-toolkit.

To stop and remove everything, use:
```
shell> ./make.sh down
```
The port 3000 will be exposed to access Orchestrator UI via:
```
http://localhost:3000
```
To access mysql insatnces you can run (install mysql client first): 
```
mysql -uroot -p -h [mysql-master|mysql-replica1|mysql-replica2] (password is in .env file) 
```
To run any tool from the toolkit run: 
```
docker-compose run --rm percona-toolkit pt-mysql-summary --host=mysql-replica1 --user="toolkit" --password="Toolkit!" 
```
* replace the tool to your desired one
