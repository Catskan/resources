#Use the official debian slim image
FROM debian:stable-slim

#Declare all arguments (variables) will used by dockerfile layers
ARG python_version=3.11.0

ARG OS
#Download Python archive from official URL
ADD https://www.python.org/ftp/python/3.11.0/Python-$python_version.tgz /tmp/Python-$python_version.tgz

#Add user /bin directory to the PATH
ENV PATH="${PATH}:/home/aurelien/.local/bin"

#Copy the public key of the destination SSH server
COPY ./Containers/Linux/Debian-Ansible/id_rsa.pub /home/aurelien/.ssh/id_rsa.pub

#Create a user with home directory to install ansible inside it
RUN useradd aurelien && chown -R aurelien:aurelien /home/aurelien/

#Build & Install Python3.11 and other packages from sources
RUN apt update && apt dist-upgrade -y && apt install cmake gcc pkg-config build-essential zlib1g-dev openssh-client \
    libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev curl iputils-ping netcat iproute2 openssh-server -y \
    && tar xzf /tmp/Python-$python_version.tgz -C /tmp/ && cd /tmp/Python-$python_version \ 
    && ./configure --enable-optimizations && make && make install \
    && rm * /tmp

#Setting up the openssh-server
RUN sed -i 's/Port 3434/PermitRootLogin yes/Protocol 2/AllowUsers aurelien/AuthorizedKeysFile %h/.ssh/authorized_keys' /etc/ssh/sshd_config

#Run the next dockerfiles layers as aurelien user
USER aurelien

#Install Ansible and Ansible's modules inside the user's home
RUN python3 -m pip install --user ansible && python3 -m pip install argcomplete && python3 -m pip install docker \
    && python3 -m pip install pywinrm \
    && activate-global-python-argcomplete --user && ansible-galaxy collection install ansible.windows && ansible-galaxy collection install kewlfft.aur
    
CMD ["tail", "-f", "/dev/null"]