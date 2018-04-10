FROM node:8@sha256:a4c4106ddda19c2c228cbdfbc0f0d7a5f27c383b0486f88fc2c2c40153763cf5
ENV NPM_CONFIG_LOGLEVEL warn
WORKDIR /tmp
RUN useradd -ms /bin/bash -d /usr/local/learninglocker learninglocker
RUN apt-get -y -q install curl && curl -o- -L http://lrnloc.kr/installv2 > deployll.sh && bash deployll.sh -y 5
EXPOSE 80
WORKDIR /usr/local/learninglocker
CMD service mongodb start && service redis-server start && su - learninglocker -c "cd /usr/local/learninglocker/current/webapp; pm2 start pm2/all.json; cd /usr/local/learninglocker/current/xapi; pm2 start pm2/xapi.json" && service nginx start && bash
