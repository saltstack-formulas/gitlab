{% if grains['os_family'] == 'RedHat' %}
# https://github.com/gitlabhq/gitlab-recipes/tree/master/install/centos
PUIAS_6_computational:
  pkgrepo.managed:
    - humanname: PUIAS computational Base $releasever - $basearch
    - gpgcheck: 1
    - gpgkey: http://springdale.math.ias.edu/data/puias/6/x86_64/os/RPM-GPG-KEY-puias
    - mirrorlist: http://puias.math.ias.edu/data/puias/computational/$releasever/$basearch/mirrorlist

{% elif grains['os_family'] == 'Debian' %}
{# TODO: Handling of packages should be moved to map.jinja #}
{# Gitlab 9.2+ requires golang-1.8+ which requires backports on Debian 9 and Artful repositories on Ubuntu #}
{%- set distro = grains.oscodename %}
gitlab-distro-backports:
  file.managed:
    - name: /etc/apt/preferences.d/55_gitlab_req_backports
    {%- if grains.os == "Ubuntu" and grains.osrelease_info[0] < 17 %}
    - contents: |
        Package: golang
        Pin: release o=Ubuntu,a=artful
        Pin-Priority: 901
    {%- else %}
    - contents: |
        Package: golang
        Pin: release o=Debian Backports,a={{ distro }}-backports
        Pin-Priority: 901
    {%- endif %}
  pkgrepo.managed:
    {%- if grains.os == "Ubuntu" and grains.osrelease_info[0] < 17 %}
    - name: deb http://archive.ubuntu.com/ubuntu artful main
    {%- else %}
    - name: deb http://httpredir.debian.org/debian {{ distro }}-backports main
    {%- endif %}
    - file: /etc/apt/sources.list.d/gitlab_req_backports.list

{# Gitlab 10.3+ requires nodejs-6+ but is not available in Debian 10 and not before Ubuntu 17.10 #}
gitlab-nodejs-repo-mgmt-pkgs:
  pkg.installed:
    - names:
        - python-apt
        - apt-transport-https
    - require_in:
        - pkgrepo: gitlab-nodejs-repo
        - pkgrepo: gitlab-yarn-repo

gitlab-nodejs-repo:
  pkgrepo.managed:
    - name: deb https://deb.nodesource.com/node_6.x {{ grains.oscodename|lower }} main
    - file: /etc/apt/sources.list.d/nodesource_6.list
    - key_url: salt://gitlab/files/nodesource.gpg.key

gitlab-nodejs-preference:
  file.managed:
    - name: /etc/apt/preferences.d/90_nodesource
    - contents: |
        Package: nodejs
        Pin: release o=Node source,l=Node source
        Pin-Priority: 901

gitlab-yarn-repo:
  pkgrepo.managed:
    - name: deb https://dl.yarnpkg.com/debian/ stable main
    - file: /etc/apt/sources.list.d/yarn.list
    - key_url: salt://gitlab/files/dl.yarn.com.key
{% endif %}
