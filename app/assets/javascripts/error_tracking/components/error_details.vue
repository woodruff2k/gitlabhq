<script>
import { mapActions, mapGetters, mapState } from 'vuex';
import dateFormat from 'dateformat';
import createFlash from '~/flash';
import {
  GlDeprecatedButton,
  GlFormInput,
  GlLink,
  GlLoadingIcon,
  GlBadge,
  GlAlert,
  GlSprintf,
  GlDropdown,
  GlDropdownItem,
  GlDropdownDivider,
} from '@gitlab/ui';
import { __, sprintf, n__ } from '~/locale';
import Icon from '~/vue_shared/components/icon.vue';
import TooltipOnTruncate from '~/vue_shared/components/tooltip_on_truncate.vue';
import Stacktrace from './stacktrace.vue';
import TrackEventDirective from '~/vue_shared/directives/track_event';
import timeagoMixin from '~/vue_shared/mixins/timeago';
import { trackClickErrorLinkToSentryOptions } from '../utils';
import { severityLevel, severityLevelVariant, errorStatus } from './constants';

import query from '../queries/details.query.graphql';

const SENTRY_TIMEOUT = 10000;

export default {
  components: {
    GlDeprecatedButton,
    GlFormInput,
    GlLink,
    GlLoadingIcon,
    TooltipOnTruncate,
    Icon,
    Stacktrace,
    GlBadge,
    GlAlert,
    GlSprintf,
    GlDropdown,
    GlDropdownItem,
    GlDropdownDivider,
  },
  directives: {
    TrackEvent: TrackEventDirective,
  },
  mixins: [timeagoMixin],
  props: {
    issueUpdatePath: {
      type: String,
      required: true,
    },
    issueId: {
      type: String,
      required: true,
    },
    projectPath: {
      type: String,
      required: true,
    },
    issueStackTracePath: {
      type: String,
      required: true,
    },
    projectIssuesPath: {
      type: String,
      required: true,
    },
    csrfToken: {
      type: String,
      required: true,
    },
  },
  apollo: {
    error: {
      query,
      variables() {
        return {
          fullPath: this.projectPath,
          errorId: `gid://gitlab/Gitlab::ErrorTracking::DetailedError/${this.issueId}`,
        };
      },
      pollInterval: 2000,
      update: data => data.project.sentryErrors.detailedError,
      error: () => createFlash(__('Failed to load error details from Sentry.')),
      result(res) {
        if (res.data.project?.sentryErrors?.detailedError) {
          this.$apollo.queries.error.stopPolling();
          this.setStatus(this.error.status);
        } else {
          this.onNoApolloResult();
        }
      },
    },
  },
  data() {
    return {
      error: null,
      errorLoading: true,
      errorPollTimeout: 0,
      issueCreationInProgress: false,
      isAlertVisible: false,
      closedIssueId: null,
    };
  },
  computed: {
    ...mapState('details', [
      'loadingStacktrace',
      'stacktraceData',
      'updatingResolveStatus',
      'updatingIgnoreStatus',
      'errorStatus',
    ]),
    ...mapGetters('details', ['stacktrace']),
    firstReleaseLink() {
      return `${this.error.externalBaseUrl}/releases/${this.error.firstReleaseShortVersion}`;
    },
    lastReleaseLink() {
      return `${this.error.externalBaseUrl}/releases/${this.error.lastReleaseShortVersion}`;
    },
    showStacktrace() {
      return Boolean(this.stacktrace?.length);
    },
    issueTitle() {
      return this.error.title;
    },
    issueDescription() {
      return sprintf(
        __(
          '%{description}- Sentry event: %{errorUrl}- First seen: %{firstSeen}- Last seen: %{lastSeen} %{countLabel}: %{count}%{userCountLabel}: %{userCount}',
        ),
        {
          description: '# Error Details:\n',
          errorUrl: `${this.error.externalUrl}\n`,
          firstSeen: `\n${this.error.firstSeen}\n`,
          lastSeen: `${this.error.lastSeen}\n`,
          countLabel: n__('- Event', '- Events', this.error.count),
          count: `${this.error.count}\n`,
          userCountLabel: n__('- User', '- Users', this.error.userCount),
          userCount: `${this.error.userCount}\n`,
        },
        false,
      );
    },
    issueUpdateInProgress() {
      return (
        this.updatingIgnoreStatus || this.updatingResolveStatus || this.issueCreationInProgress
      );
    },
    errorLevel() {
      return sprintf(__('level: %{level}'), { level: this.error.tags.level });
    },
    errorSeverityVariant() {
      return (
        severityLevelVariant[this.error.tags.level] || severityLevelVariant[severityLevel.ERROR]
      );
    },
    ignoreBtnLabel() {
      return this.errorStatus !== errorStatus.IGNORED ? __('Ignore') : __('Undo ignore');
    },
    resolveBtnLabel() {
      return this.errorStatus !== errorStatus.RESOLVED ? __('Resolve') : __('Unresolve');
    },
  },
  watch: {
    error(val) {
      if (val) {
        this.errorLoading = false;
      }
    },
  },
  mounted() {
    this.startPollingStacktrace(this.issueStackTracePath);
    this.errorPollTimeout = Date.now() + SENTRY_TIMEOUT;
    this.$apollo.queries.error.setOptions({
      fetchPolicy: 'cache-and-network',
    });
  },
  methods: {
    ...mapActions('details', [
      'startPollingStacktrace',
      'updateStatus',
      'setStatus',
      'updateResolveStatus',
      'updateIgnoreStatus',
    ]),
    trackClickErrorLinkToSentryOptions,
    createIssue() {
      this.issueCreationInProgress = true;
      this.$refs.sentryIssueForm.submit();
    },
    onIgnoreStatusUpdate() {
      const status =
        this.errorStatus === errorStatus.IGNORED ? errorStatus.UNRESOLVED : errorStatus.IGNORED;
      this.updateIgnoreStatus({ endpoint: this.issueUpdatePath, status });
    },
    onResolveStatusUpdate() {
      const status =
        this.errorStatus === errorStatus.RESOLVED ? errorStatus.UNRESOLVED : errorStatus.RESOLVED;

      // eslint-disable-next-line promise/catch-or-return
      this.updateResolveStatus({ endpoint: this.issueUpdatePath, status }).then(res => {
        this.closedIssueId = res.closed_issue_iid;
        if (this.closedIssueId) {
          this.isAlertVisible = true;
        }
      });
    },
    onNoApolloResult() {
      if (Date.now() > this.errorPollTimeout) {
        this.$apollo.queries.error.stopPolling();
        this.errorLoading = false;
        createFlash(__('Could not connect to Sentry. Refresh the page to try again.'), 'warning');
      }
    },
    formatDate(date) {
      return `${this.timeFormatted(date)} (${dateFormat(date, 'UTC:yyyy-mm-dd h:MM:ssTT Z')})`;
    },
  },
};
</script>

<template>
  <div>
    <div v-if="errorLoading" class="py-3">
      <gl-loading-icon size="lg" />
    </div>
    <div v-else-if="error" class="error-details">
      <gl-alert v-if="isAlertVisible" @dismiss="isAlertVisible = false">
        <gl-sprintf
          :message="
            __('The associated issue #%{issueId} has been closed as the error is now resolved.')
          "
        >
          <template #issueId>
            <span>{{ closedIssueId }}</span>
          </template>
        </gl-sprintf>
      </gl-alert>

      <div class="error-details-header d-flex py-2 justify-content-between">
        <div
          v-if="!loadingStacktrace && stacktrace"
          class="error-details-meta my-auto"
          data-qa-selector="reported_text"
        >
          <gl-sprintf :message="__('Reported %{timeAgo} by %{reportedBy}')">
            <template #reportedBy>
              <strong class="error-details-meta-culprit">{{ error.culprit }}</strong>
            </template>
            <template #timeAgo>
              {{ timeFormatted(stacktraceData.date_received) }}
            </template>
          </gl-sprintf>
        </div>
        <div class="error-details-actions">
          <div class="d-inline-flex bv-d-sm-down-none">
            <gl-deprecated-button
              :loading="updatingIgnoreStatus"
              data-qa-selector="update_ignore_status_button"
              @click="onIgnoreStatusUpdate"
            >
              {{ ignoreBtnLabel }}
            </gl-deprecated-button>
            <gl-deprecated-button
              class="btn-outline-info ml-2"
              :loading="updatingResolveStatus"
              data-qa-selector="update_resolve_status_button"
              @click="onResolveStatusUpdate"
            >
              {{ resolveBtnLabel }}
            </gl-deprecated-button>
            <gl-deprecated-button
              v-if="error.gitlabIssuePath"
              class="ml-2"
              data-qa-selector="view_issue_button"
              :href="error.gitlabIssuePath"
              variant="success"
            >
              {{ __('View issue') }}
            </gl-deprecated-button>
            <form
              ref="sentryIssueForm"
              :action="projectIssuesPath"
              method="POST"
              class="d-inline-block ml-2"
            >
              <gl-form-input class="hidden" name="issue[title]" :value="issueTitle" />
              <input name="issue[description]" :value="issueDescription" type="hidden" />
              <gl-form-input
                :value="error.sentryId"
                class="hidden"
                name="issue[sentry_issue_attributes][sentry_issue_identifier]"
              />
              <gl-form-input :value="csrfToken" class="hidden" name="authenticity_token" />
              <gl-deprecated-button
                v-if="!error.gitlabIssuePath"
                class="btn-success"
                :loading="issueCreationInProgress"
                data-qa-selector="create_issue_button"
                @click="createIssue"
              >
                {{ __('Create issue') }}
              </gl-deprecated-button>
            </form>
          </div>
          <gl-dropdown
            text="Options"
            class="error-details-options d-md-none"
            right
            :disabled="issueUpdateInProgress"
          >
            <gl-dropdown-item
              data-qa-selector="update_ignore_status_button"
              @click="onIgnoreStatusUpdate"
              >{{ ignoreBtnLabel }}</gl-dropdown-item
            >
            <gl-dropdown-item
              data-qa-selector="update_resolve_status_button"
              @click="onResolveStatusUpdate"
              >{{ resolveBtnLabel }}</gl-dropdown-item
            >
            <gl-dropdown-divider />
            <gl-dropdown-item
              v-if="error.gitlabIssuePath"
              data-qa-selector="view_issue_button"
              :href="error.gitlabIssuePath"
              variant="success"
              >{{ __('View issue') }}</gl-dropdown-item
            >
            <gl-dropdown-item
              v-if="!error.gitlabIssuePath"
              :loading="issueCreationInProgress"
              data-qa-selector="create_issue_button"
              @click="createIssue"
              >{{ __('Create issue') }}</gl-dropdown-item
            >
          </gl-dropdown>
        </div>
      </div>
      <div>
        <tooltip-on-truncate :title="error.title" truncate-target="child" placement="top">
          <h2 class="text-truncate">{{ error.title }}</h2>
        </tooltip-on-truncate>
        <template v-if="error.tags">
          <gl-badge
            v-if="error.tags.level"
            :variant="errorSeverityVariant"
            class="rounded-pill mr-2"
          >
            {{ errorLevel }}
          </gl-badge>
          <gl-badge v-if="error.tags.logger" variant="light" class="rounded-pill"
            >{{ error.tags.logger }}
          </gl-badge>
        </template>
        <ul>
          <li v-if="error.gitlabCommit">
            <strong class="bold">{{ __('GitLab commit') }}:</strong>
            <gl-link :href="error.gitlabCommitPath">
              <span>{{ error.gitlabCommit.substr(0, 10) }}</span>
            </gl-link>
          </li>
          <li v-if="error.gitlabIssuePath">
            <strong class="bold">{{ __('GitLab Issue') }}:</strong>
            <gl-link :href="error.gitlabIssuePath">
              <span>{{ error.gitlabIssuePath }}</span>
            </gl-link>
          </li>
          <li>
            <strong class="bold">{{ __('Sentry event') }}:</strong>
            <gl-link
              v-track-event="trackClickErrorLinkToSentryOptions(error.externalUrl)"
              :href="error.externalUrl"
              target="_blank"
            >
              <span class="text-truncate">{{ error.externalUrl }}</span>
              <icon name="external-link" class="ml-1 flex-shrink-0" />
            </gl-link>
          </li>
          <li v-if="error.firstReleaseShortVersion">
            <strong class="bold">{{ __('First seen') }}:</strong>
            {{ formatDate(error.firstSeen) }}
            <gl-link :href="firstReleaseLink" target="_blank">
              <span>{{ __('Release') }}: {{ error.firstReleaseShortVersion.substr(0, 10) }}</span>
            </gl-link>
          </li>
          <li v-if="error.lastReleaseShortVersion">
            <strong class="bold">{{ __('Last seen') }}:</strong>
            {{ formatDate(error.lastSeen) }}
            <gl-link :href="lastReleaseLink" target="_blank">
              <span>{{ __('Release') }}: {{ error.lastReleaseShortVersion.substr(0, 10) }}</span>
            </gl-link>
          </li>
          <li>
            <strong class="bold">{{ __('Events') }}:</strong>
            <span>{{ error.count }}</span>
          </li>
          <li>
            <strong class="bold">{{ __('Users') }}:</strong>
            <span>{{ error.userCount }}</span>
          </li>
        </ul>

        <div v-if="loadingStacktrace" class="py-3">
          <gl-loading-icon size="lg" />
        </div>

        <template v-else-if="showStacktrace">
          <h3 class="my-4">{{ __('Stack trace') }}</h3>
          <stacktrace :entries="stacktrace" />
        </template>
      </div>
    </div>
  </div>
</template>
