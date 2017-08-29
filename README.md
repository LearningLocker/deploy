# LearningLocker OpenSource installer

This is the HT2 Learning Locker opensource installer. It's designed to walk you through the process of 
downloading the code, running any steps needed (such as compilation) and generally setting up a complete 
working instance. To do this it attempts to detect your operating system, install any software needed
then pull the code down from Github, run the build steps and install to whichever directory you've 
specified. You'll be prompted for everything required while you run the script.

Due to the neccesity to install software, you will need to run this script as the root user.


### QuickStart
As root run:  
	`bash llv2_build.sh`  
	or  
	`./llv2_build.sh`  
And just follow the prompts given


### Configuration
The software creates a `.env` file in your install directory and within the `xapi/` sub-directory. You can
configure things here if you want to use external mongo or redis servers or change any ports in use.
In addition, the software uses nginx to route traffic. Routing rules are defined in the learninglocker 
nginx configuration which is installed as part of the script. This varies depending on OS but are 
currently:

	CentOS / Fedora : /etc/nginx/conf.d/learninglocker.conf
	
	Debian / Ubuntu : /etc/nginx/sites-available/learninglocker.conf


### Running / restarting
The system works by creating four Node.js server instances running under PM2 (a Node process management suite) which get traffic routed 
to them from the nginx config. In order to make sure that everything restarts automatically, the build 
process creates a restart script which you can run as follows:

	service pm2-{USER} restart
	
The user in this is the user you opted to install Learning Locker under. If you went with the default of
'node' then this would be:

	service pm2-node restart


### Supported Operating systems
	CentOS
	Fedora
	Ubuntu
	Debian

### Software Required - Installed automatically
	git
	python
	build tools (ie: GCC)
	xvfb
	curl
	nodejs
	yarn
	pm2
	nginx

### Software Required - Optional installs
	MongoDB
	Redis

In addition to the above, the software will require access to an instance of MongoDB and Redis. By default, 
the configuration points to instances on localhost and will offer to install mongo & redis for you if you
want to get everything working on a single server.


### Recommended hardware
While there is no specific hardware requirement beyond a reasonably modern 64bit x86_64 computer, you should
pay attention to your memory usage. If you're running redis and / or mongo on the same server as learning 
locker then you'll need more memory than without. Server load will depend on the use cases for your particular
organisation.
