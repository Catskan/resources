#Use the official debian slim image
FROM debian:stable-slim

#Declare all arguments (variables) will used by dockerfile layers
ARG python_version=3.11.0

#Download Python archive from official URL
ADD https://www.python.org/ftp/python/3.11.0/Python-$python_version.tgz /tmp/Python-$python_version.tgz

#Add user /bin directory to the PATH
ENV PATH="${PATH}:/home/aurelien/.local/bin"

#Copy the public key of the destination SSH server
COPY ./Containers/Linux/Debian-Ansible/id_rsa /home/aurelien/.ssh/id_rsa

#Create a user with home directory to install ansible inside it
RUN useradd aurelien && chown -R aurelien:aurelien /home/aurelien/

#Build & Install Python 3.11 from sources
RUN apt update && apt dist-upgrade -y && apt install cmake gcc pkg-config build-essential zlib1g-dev openssh-client \
    libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev curl -y \
    && tar xzf /tmp/Python-$python_version.tgz -C /tmp/ && cd /tmp/Python-$python_version \ 
    && ./configure --enable-optimizations && make && make install

#Run the next dockerfiles layers as aurelien user
USER aurelien

#Install Ansible and Ansible's modules inside the user's home
RUN python3 -m pip install --user ansible && python3 -m pip install argcomplete && python3 -m pip install docker \
    && python3 -m pip install pywinrm \
    && activate-global-python-argcomplete --user
    

ENTRYPOINT ["tail", "-f", "/dev/null"]