## Licensed to Cloudera, Inc. under one
## or more contributor license agreements.  See the NOTICE file
## distributed with this work for additional information
## regarding copyright ownership.  Cloudera, Inc. licenses this file
## to you under the Apache License, Version 2.0 (the
## "License"); you may not use this file except in compliance
## with the License.  You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

<%!
from django.utils.translation import ugettext as _

from notebook.conf import ENABLE_QUERY_SCHEDULING

from desktop.conf import IS_EMBEDDED, IS_MULTICLUSTER_ONLY, IS_K8S_ONLY, URL_PREFIX
from desktop.lib.i18n import smart_unicode
from desktop.views import _ko
%>

<%def name="jobBrowserLinks()">

  <script type="text/html" id="hue-job-browser-links-template">
    <div class="btn-group pull-right">
      % if IS_K8S_ONLY.get():
        <a class="btn btn-flat" style="padding-right: 4px" title="${_('Query browser')}" data-bind="hueLink: '/jobbrowser#!queries', click: function() { huePubSub.publish('show.jobs.panel', {interface: 'queries'}); huePubSub.publish('hide.jobs.panel'); }">
          <span>${ _('Queries') }</span>
        </a>
      % else:
        <a class="btn btn-flat" style="padding-right: 4px" title="${_('Job browser')}" data-bind="hueLink: '/jobbrowser#!jobs', click: function() { huePubSub.publish('hide.jobs.panel'); }">
          <span>${ _('Queries') if IS_EMBEDDED.get() or IS_MULTICLUSTER_ONLY.get() else _('Jobs') }</span>
        </a>
      % endif
      <button class="btn btn-flat btn-toggle-jobs-panel" title="${_('Jobs preview')}" data-bind="click: function() { huePubSub.publish('toggle.jobs.panel'); }, style: {'paddingLeft': jobCount() > 0 ? '0': '4px'}">
        <span class="jobs-badge" data-bind="visible: jobCount() > 0, text: jobCount"></span>
        <i class="fa fa-tasks"></i>
      </button>
    </div>
  </script>

  <script type="text/javascript">
    (function () {
      var JB_CHECK_INTERVAL_IN_MILLIS = 30000;

      var JobBrowserPanel = function (params) {
        var self = this;

        var $container = $(HUE_CONTAINER);
        var $jobsPanel = $('#jobsPanel');
        var $toggle = $('.btn-toggle-jobs-panel');

        var reposition = function () {
          $jobsPanel.css('top', ($toggle.offset().top + $toggle.height() + 15) + 'px');
          $jobsPanel.css('left', ($container.offset().left + $container.width() - 630) + 'px')
        };

        huePubSub.subscribe('hide.jobs.panel', function () {
          $(window).off('resize', reposition);
          $jobsPanel.hide();
        });

        huePubSub.subscribe('show.jobs.panel', function (options) {
          if ('${ IS_K8S_ONLY.get() }' == 'True') {
            huePubSub.publish('context.selector.set.cluster', 'impala');
          };
          
          huePubSub.publish('hide.history.panel');
          $(window).on('resize', reposition);
          reposition();
          $jobsPanel.show();
          huePubSub.publish('mini.jb.navigate', {section: options && options.interface ? options.interface : 'jobs', compute: options && options.compute});
          if (options && options.id) {
            huePubSub.publish('mini.jb.open.job', options.id);
          }
        });

        huePubSub.subscribe('toggle.jobs.panel', function () {
          if ($jobsPanel.is(':visible')){
            huePubSub.publish('hide.jobs.panel');
          }
          else {
            huePubSub.publish('show.jobs.panel');
          }
        });

        self.jobCounts = ko.observable({'yarn': 0, 'schedules': 0});
        self.jobCount = ko.pureComputed(function() {
          var total = 0;
          Object.keys(self.jobCounts()).forEach(function (value) {
            total += self.jobCounts()[value];
          });
          return total;
        });
        self.onePageViewModel = params.onePageViewModel;

        var lastYarnBrowserRequest = null;
        var checkYarnBrowserStatus = function() {
          return $.post("/${ URL_PREFIX.get() }jobbrowser/jobs/", {
              "format": "json",
              "state": "running",
              "user": "${user.username}"
            },
            function(data) {
              if (data != null && data.jobs != null) {
                huePubSub.publish('jobbrowser.data', data.jobs);
                self.jobCounts()['yarn'] = data.jobs.length;
                self.jobCounts.valueHasMutated();
              }
          })
        };
        var lastScheduleBrowserRequest = null;
        var checkScheduleBrowserStatus = function() {
          return $.post("/${ URL_PREFIX.get() }jobbrowser/api/jobs", {
              interface: ko.mapping.toJSON("schedules"),
              filters: ko.mapping.toJSON([
                  {"text": "user:${user.username}"},
                  {"time": {"time_value": 7, "time_unit": "days"}},
                  {"states": ["running"]},
                  {"pagination": {"page": 1, "offset": 1, "limit": 1}}
              ])
            },
            function(data) {
              if (data != null && data.total != null) {
                huePubSub.publish('jobbrowser.schedule.data', data.apps);
                self.jobCounts()['schedules'] = data.total;
                self.jobCounts.valueHasMutated();
              }
          })
        };

        var checkJobBrowserStatus = function() {
          lastYarnBrowserRequest = checkYarnBrowserStatus();
          % if ENABLE_QUERY_SCHEDULING.get():
            lastScheduleBrowserRequest = checkScheduleBrowserStatus();
          % endif

          $.when.apply($, [
            lastYarnBrowserRequest,
            % if ENABLE_QUERY_SCHEDULING.get():
              lastScheduleBrowserRequest
            % endif
          ])
          .done(function () {
            checkJobBrowserStatusIdx = window.setTimeout(checkJobBrowserStatus, JB_CHECK_INTERVAL_IN_MILLIS);
           })
          .fail(function () {
            window.clearTimeout(checkJobBrowserStatusIdx);
          });
        };


        // Load the mini jobbrowser
        $.ajax({
          url: '/${ URL_PREFIX.get() }jobbrowser/apps?is_embeddable=true&is_mini=true',
          beforeSend: function (xhr) {
            xhr.setRequestHeader('X-Requested-With', 'Hue');
          },
          dataType: 'html',
          success: function (response) {
            params.onePageViewModel.processHeaders(response).done(function (rawHtml) {
              $('#mini_jobbrowser').html(rawHtml);
              //ko.bindingHandlers.delayedOverflow.init($('#mini_jobbrowser')[0]);
            });
          }
        });

        % if not IS_EMBEDDED.get() and not IS_K8S_ONLY.get():
        var checkJobBrowserStatusIdx = window.setTimeout(checkJobBrowserStatus, 10);

        huePubSub.subscribe('check.job.browser', checkYarnBrowserStatus);
        huePubSub.subscribe('check.schedules.browser', checkScheduleBrowserStatus);
        % endif
      };

      ko.components.register('hue-job-browser-links', {
        viewModel: JobBrowserPanel,
        template: { element: 'hue-job-browser-links-template' }
      });
    })();
  </script>
</%def>
