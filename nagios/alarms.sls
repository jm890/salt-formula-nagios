{%- from "nagios/map.jinja" import server with context %}
{%- if server.enabled %}
include:
- nagios.server
{% if server.dynamic.stacklight_alarms is mapping and server.dynamic.stacklight_alarms.enabled is defined and server.dynamic.stacklight_alarms.enabled %}

{% set grain_hostname = server.dynamic.get('grain_hostname', 'nodename') %}
{% set alarms = {} %}
{% set commands = {} %}
{%- for node_name, node_grains in salt['mine.get']('*', 'grains.items').items() %}

{%- if node_grains.heka is defined and node_grains.heka.metric_collector is mapping %}

{% set triggers = node_grains.heka.metric_collector.get('trigger', {}) %}
{% for alarm_id, alarm_def in node_grains.heka.metric_collector.get('alarm', {}).items() %}
{% if alarm_def.get('alerting', 'enabled') != 'disabled' %}

{% set check_command = 'check_dummy_unknown_' + node_grains[grain_hostname] + alarm_id %}
{% set threshold = salt['nagios_alarming.threshold'](alarm_def, triggers) %}

{% do commands.update({check_command: { 'command_line': 'check_dummy 3 "No data received for at least {} seconds"'.format(threshold)}}) %}

{% do alarms.update(salt['nagios_alarming.alarm_to_service'](
                     node_grains[grain_hostname],
                     alarm_id,
                     alarm_def,
                     check_command,
                     threshold,
                     {'use': server.dynamic.stacklight_alarms.get('service_template', server.default_service_template)})) %}
{% endif %}
{% endfor %}
{%- endif %} {# end metric_collector alarms #}

{% endfor %}

nagios alarm service configurations:
  file.managed:
    - name: {{ server.objects_cfg_dir }}/{{ server.objects_file_prefix }}.alarms.cfg
    - source: salt://nagios/files/services.cfg
    - template: jinja
    - user: root
    - mode: 644
    - defaults:
      services: {{ alarms }}
    - watch_in:
      - service: {{ server.service }}

{% if commands.keys()|length > 0 %}
Nagios alarm dummy commands configurations:
  file.managed:
    - name: {{ server.objects_cfg_dir }}/{{ server.objects_file_prefix }}.alarms-commands.cfg
    - template: jinja
    - user: root
    - mode: 644
    - contents: |
{% for cmd_id, conf in commands.items() %}
        define command {
{% if not conf.command_line[0] == '/' %}
          command_line {{server.plugin_dir }}/{{ conf.command_line }}
{% else %}
          command_line {{ conf.command_line }}
{% endif %}
          command_name {{ conf.command_name|default(cmd_id) }}
        }
{% endfor %}
    - watch_in:
      - service: {{ server.service }}
{% endif %}
{% else %}
nagios alarm service configurations purge:
  file.absent:
    - name: {{ server.objects_cfg_dir }}/{{ server.objects_file_prefix }}.alarms.cfg
    - watch_in:
      - service: {{ server.service }}

Nagios alarm dummy commands configurations purge:
  file.absent:
    - name: {{ server.objects_cfg_dir }}/{{ server.objects_file_prefix }}.alarms-commands.cfg
    - watch_in:
      - service: {{ server.service }}
{% endif %}
{% endif %}