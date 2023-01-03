#Use the official debian slim image
FROM debian:stable-slim as python

ARG python_version=3.11.1

ARG OS
#Install Deb packages to build Python
RUN apt update && apt dist-upgrade -y \
    && apt install cmake gcc pkg-config build-essential zlib1g-dev \
    libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev -y

#Download Python archive from official URL
ADD https://www.python.org/ftp/python/$python_version/Python-$python_version.tgz /tmp/Python-$python_version.tgz

RUN tar xzf /tmp/Python-$python_version.tgz -C /tmp/ && cd /tmp/Python-$python_version \ 
    && ./configure --enable-optimizations && make && make install

FROM python as main

RUN apt update && apt install openssh-client \
    curl iputils-ping netcat iproute2 nano unzip npm jq -y

# #Add user /bin directory to the PATH
ENV PATH="${PATH}:/home/aurelien/.local/bin"

COPY ./Containers/Linux/Debian-Ansible/entrypoint.sh /etc/bin/entrypoint.sh

#Create a user with home directory to install ansible inside it
RUN useradd aurelien && mkdir /home/aurelien && chown -R aurelien:aurelien /home/aurelien/
RUN chmod +x /etc/bin/entrypoint.sh

#Setting up the openssh-server
RUN sed -i "s/AuthorizedKeysFile /.ssh_keys/" /etc/ssh/ssh_config 
#RUN sed -i "s/IdentityFile /.ssh_keys/id_rsa_debian_ansible/" /etc/ssh/ssh_config

#Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \ 
    && unzip awscliv2.zip && ./aws/install && rm awscliv2.zip && rm -r ./aws

RUN npm install -g @bitwarden/cli

#Run the next dockerfiles layers as aurelien user
USER aurelien

#Install Ansible and Ansible's modules inside the user's home
RUN python3 -m pip install --upgrade pip && python3 -m pip install --user ansible && python3 -m pip install argcomplete \
    && python3 -m pip install docker \
    && python3 -m pip install pywinrm && python3 -m pip install boto3 && python3 -m pip install botocore \
    && activate-global-python-argcomplete --user && ansible-galaxy collection install ansible.windows \
    && ansible-galaxy collection install community.general
    
CMD ["/etc/bin/entrypoint.sh"]