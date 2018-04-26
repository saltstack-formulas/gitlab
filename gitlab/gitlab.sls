include:
  - postgres
  - gitlab.ruby

{% set root_dir = salt['pillar.get']('gitlab:lookup:root_dir', '/home/git') %}
{% set repositories = salt['pillar.get']('gitlab:lookup:repositories', root_dir ~ '/repositories') %}
{% set sockets_dir = salt['pillar.get']('gitlab:lookup:sockets_dir', root_dir ~ '/var/sockets') %}
{% set pids_dir = salt['pillar.get']('gitlab:lookup:pids_dir', root_dir ~ '/var/pids') %}
{% set logs_dir = salt['pillar.get']('gitlab:lookup:logs_dir', root_dir ~ '/var/logs') %}
{% set uploads_dir = salt['pillar.get']('gitlab:lookup:uploads_dir', root_dir ~ '/var/uploads') %}
{% set lib_dir = salt['pillar.get']('gitlab:lookup:lib_dir', root_dir ~ '/libraries') %}

{% set active_db = salt['pillar.get']('gitlab:databases:production', 'paf') %}
{% set db_user, db_user_infos = salt['pillar.get']('postgres:users').items()[0] %}

{% set gitlab_dir = root_dir ~ "/gitlab" %}
{% if salt['pillar.get']('gitlab:archives:enabled', false) %}
    {% set gitlab_dir_content = lib_dir ~ '/gitlab/' ~ salt['pillar.get']('gitlab:archives:sources:gitlab:content') %}
{% else %}
    {% set gitlab_dir_content = gitlab_dir %}
{% endif %}

{% if salt['pillar.get']('gitlab:archives:enabled', false) %}
gitlab-fetcher:
  archive.extracted:
    - name: {{ lib_dir }}/gitlab
    - source: {{ salt['pillar.get']('gitlab:archives:sources:gitlab:source') }}
    - source_hash: md5={{ salt['pillar.get']('gitlab:archives:sources:gitlab:md5') }}
    - archive_format: tar
    - if_missing: {{ gitlab_dir_content }}
    - keep: True

gitlab-chown:
  file.directory:
    - name: {{ gitlab_dir_content }}
    - user: git
    - group: git
    - recurse:
      - user
    - onchanges:
      - archive: gitlab-fetcher

gitlab-lib-symlink:
  file.symlink:
    - name: {{ gitlab_dir }}
    - target: {{ gitlab_dir_content }}
  require:
    - file: gitlab-fetcher
{% else %}
gitlab-fetcher:
  git.latest:
    - name: https://gitlab.com/gitlab-org/gitlab-ce.git
    - rev: {{ salt['pillar.get']('gitlab:gitlab_version') }}
    - user: git
    - target: {{ gitlab_dir }}
    - force: True
    - require:
      - pkg: gitlab-deps
      - pkg: git
      - sls: gitlab.ruby
      - cmd: gitlab-shell
      - user: git-user
{% endif %}

# https://gitlab.com/gitlab-org/gitlab-ce/blob/master/config/gitlab.yml.example
gitlab-config:
  file.managed:
    - name: {{ root_dir }}/gitlab/config/gitlab.yml
    - source: salt://gitlab/files/gitlab-gitlab.yml
    - template: jinja
    - user: git
    - group: git
    - mode: 640
    - require:
    {% if salt['pillar.get']('gitlab:archives:enabled', false) %}
      - archive: gitlab-fetcher
    {% else %}
      - git: gitlab-fetcher
    {% endif %}
      - user: git-user

# https://gitlab.com/gitlab-org/gitlab-ce/blob/master/config/database.yml.postgresql
gitlab-db-config:
  file.managed:
    - name: {{ root_dir }}/gitlab/config/database.yml
    - source: salt://gitlab/files/gitlab-database.yml
    - template: jinja
    - user: git
    - group: git
    - mode: 640
    - require:
    {% if salt['pillar.get']('gitlab:archives:enabled', false) %}
      - archive: gitlab-fetcher
    {% else %}
      - git: gitlab-fetcher
    {% endif %}
      - user: git-user

gitlab-redis-config:
  file.managed:
    - name: {{ root_dir }}/gitlab/config/resque.yml
    - source: salt://gitlab/files/gitlab-resque.yml
    - template: jinja
    - user: git
    - group: git
    - mode: 640
    - require:
      - user: git-user

gitlab-db-secrets:
  file.managed:
    - name: {{ root_dir }}/gitlab/config/secrets.yml
    - source: salt://gitlab/files/gitlab-secrets.yml
    - template: jinja
    - user: git
    - group: git
    - mode: 600
    - require:
    {% if salt['pillar.get']('gitlab:archives:enabled', false) %}
      - archive: gitlab-fetcher
    {% else %}
      - git: gitlab-fetcher
    {% endif %}

# https://gitlab.com/gitlab-org/gitlab-ce/blob/master/config/unicorn.rb.example
unicorn-config:
  file.managed:
    - name: {{ root_dir }}/gitlab/config/unicorn.rb
    - source: salt://gitlab/files/gitlab-unicorn.rb
    - template: jinja
    - user: git
    - group: git
    - mode: 640
    - require:
    {% if salt['pillar.get']('gitlab:archives:enabled', false) %}
      - archive: gitlab-fetcher
    {% else %}
      - git: gitlab-fetcher
    {% endif %}
      - user: git-user

# https://gitlab.com/gitlab-org/gitlab-ce/blob/master/config/initializers/rack_attack.rb.example
rack_attack-config:
  file.managed:
    - name: {{ root_dir }}/gitlab/config/initializers/rack_attack.rb
    - source: salt://gitlab/files/gitlab-rack_attack.rb
    - user: git
    - group: git
    - mode: 640
    - require:
    {% if salt['pillar.get']('gitlab:archives:enabled', false) %}
      - archive: gitlab-fetcher
    {% else %}
      - git: gitlab-fetcher
    {% endif %}
      - user: git-user

git-config:
  file.managed:
    - name: {{ root_dir }}/.gitconfig
    - source: salt://gitlab/files/gitlab-gitconfig
    - template: jinja
    - user: git
    - group: git
    - mode: 640
    - require:
      - user: git-user

git-var-mkdir:
  file.directory:
    - name: {{ root_dir }}/var
    - user: git
    - group: git
    - mode: 750

# pids_dir
{% for dir in [ sockets_dir, logs_dir ] %}
git-{{ dir }}-mkdir:
  file.directory:
    - name: {{ dir }}
    - user: git
    - group: git
    - mode: 750
{% endfor %}

gitlab-uploads_dir-mkdir:
  file.directory:
    - name: {{ uploads_dir }}
    - user: git
    - group: git
    - mode: 700

gitlab-uploads_dir-symlink:
  file.symlink:
    - name: {{ gitlab_dir }}/public/uploads
    - target: {{ uploads_dir }}
    - require:
      - file: gitlab-config
      - file: gitlab-uploads_dir-mkdir

# Hardcoded in gitlab, so, we have to create symlink
gitlab-pids_dir-symlink:
  file.symlink:
    - name: {{ pids_dir }}
    - target: {{ gitlab_dir }}/tmp/pids
  require:
    - file: gitlab-config

# When code changes, trigger upgrade procedure
# Based on https://gitlab.com/gitlab-org/gitlab-ce/blob/master/lib/gitlab/upgrader.rb
gitlab-gems:
  cmd.run:
    - user: git
    - cwd: {{ gitlab_dir }}
    - name: bundle install --deployment --without development test mysql aws kerberos
    - env:
      {%- if salt['pillar.get']('gitlab:proxy:address') %}
      - HTTP_PROXY: {{ pillar.gitlab.proxy.address }}
      - HTTPS_PROXY: {{ pillar.gitlab.proxy.address }}
      {%- endif %}
    - onchanges:
    {% if salt['pillar.get']('gitlab:archives:enabled', false) %}
      - archive: gitlab-fetcher
    {% else %}
      - git: gitlab-fetcher
    {% endif %}
    - require:
      - file: gitlab-db-config
      - file: gitlab-config
      - file: unicorn-config
      - file: rack_attack-config
      - sls: gitlab.ruby

gitlab-initialize:
  cmd.run:
    - user: git
    - cwd: {{ gitlab_dir }}
    - name: bundle exec rake gitlab:setup
    - env:
      - force: yes
      - RAILS_ENV: production
    - unless: PGPASSWORD={{ db_user_infos.password }} psql -h {{ active_db.host }} -U {{ db_user }} {{ active_db.name }} -c 'select * from users;'
    - watch:
    {% if salt['pillar.get']('gitlab:archives:enabled', false) %}
      - archive: gitlab-fetcher
    {% else %}
      - git: gitlab-fetcher
    {% endif %}
    - require:
      - cmd: gitlab-gems
      - file: gitlab-db-config

gitlab-migrate-db:
  cmd.run:
    - user: git
    - cwd: {{ gitlab_dir }}
    - name: bundle exec rake db:migrate
    - env:
      - RAILS_ENV: production
    - onchanges:
    {% if salt['pillar.get']('gitlab:archives:enabled', false) %}
      - archive: gitlab-fetcher
    {% else %}
      - git: gitlab-fetcher
    {% endif %}
    - require:
      - file: gitlab-db-config
      - file: gitlab-redis-config
      - cmd: gitlab-gems

gitlab-build-translations:
  cmd.run:
    - user: git
    - cwd: {{ gitlab_dir }}
    - name: bundle exec rake gettext:pack gettext:po_to_json
    - env:
      - RAILS_ENV: production
    - onchanges:
    {% if salt['pillar.get']('gitlab:archives:enabled', false) %}
      - archive: gitlab-fetcher
    {% else %}
      - git: gitlab-fetcher
    {% endif %}
    - require:
      - cmd: gitlab-gems

gitlab-yarn-install:
  cmd.run:
    - name: bundle exec rake yarn:install
    - user: git
    - cwd: {{ gitlab_dir }}
    - env:
      - RAILS_ENV: production
      - NODE_ENV: production
      {%- if salt['pillar.get']('gitlab:proxy:address') %}
      - YARN_PROXY: {{ pillar.gitlab.proxy.address }}
      - HTTP_PROXY: {{ pillar.gitlab.proxy.address }}
      - HTTPS_PROXY: {{ pillar.gitlab.proxy.address }}
      {%- endif %}
    - onchanges:
    {% if salt['pillar.get']('gitlab:archives:enabled', false) %}
      - archive: gitlab-fetcher
    {% else %}
      - git: gitlab-fetcher
    {% endif %}
    - require:
      - cmd: gitlab-build-translations

gitlab-recompile-assets-cache:
  cmd.run:
    - user: git
    - cwd: {{ gitlab_dir }}
    - name: bundle exec rake gitlab:assets:clean gitlab:assets:compile cache:clear
    - env:
      - RAILS_ENV: production
      - NODE_ENV: production
    - onchanges:
    {% if salt['pillar.get']('gitlab:archives:enabled', false) %}
      - archive: gitlab-fetcher
    {% else %}
      - git: gitlab-fetcher
    {% endif %}
    - require:
      - cmd: gitlab-yarn-install

{% if not salt['pillar.get']('gitlab:archives:enabled', false) %}
# Needed to be able to update tree via git
gitlab-stash:
  cmd.wait:
    - user: git
    - cwd: {{ gitlab_dir }}
    - name: git stash
    - onchanges:
      - git: gitlab-fetcher
{% endif %}

# https://gitlab.com/gitlab-org/gitlab-ce/blob/master/lib/support/init.d/gitlab.default.example
gitlab-default:
  file.managed:
    - name: /etc/default/gitlab
    - source: salt://gitlab/files/gitlab-default
    - template: jinja
    - user: root
    - group: root
    - mode: 644

# https://gitlab.com/gitlab-org/gitlab-ce/blob/master/lib/support/logrotate/gitlab
gitlab-logwatch:
  file.managed:
    - name: /etc/logrotate.d/gitlab
    - source: salt://gitlab/files/gitlab-logrotate
    - template: jinja
    - user: root
    - group: root
    - mode: 644

gitlab-respositories-dir:
  file.directory:
    - name: {{ repositories }}
    - user: git
    - group: git
    - file_mode: 0660
    - dir_mode: 2770

gitlab-service:
  file.managed:
    - name: /etc/init.d/gitlab
    - source: salt://gitlab/files/initd
    - mode: 0755
    - template: jinja
    - require:
    {% if salt['pillar.get']('gitlab:archives:enabled', false) %}
      - archive: gitlab-fetcher
    {% else %}
      - git: gitlab-fetcher
    {% endif %}
  service:
    - name: gitlab
    - running
    - enable: True
    - reload: True
    - require:
      - file: gitlab-service
#      - cmd: gitlab-initialize
      - file: gitlab-pids_dir-symlink
      - file: gitlab-uploads_dir-symlink
    - watch:
    {% if salt['pillar.get']('gitlab:archives:enabled', false) %}
      - archive: gitlab-fetcher
    {% else %}
      - git: gitlab-fetcher
    {% endif %}
      - file: gitlab-config
      - file: gitlab-db-config
      - file: gitlab-default
      - file: rack_attack-config
      - file: unicorn-config
