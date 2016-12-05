require 'spec_helper'

describe "Pipelines", feature: true, js: true do
  include GitlabRoutingHelper

  let(:project) { create(:empty_project) }
  let(:user) { create(:user) }

  before do
    login_as(user)
    project.team << [user, :developer]
  end

  describe 'GET /:project/pipelines/:id' do
    let(:project) { create(:project) }
    let(:pipeline) { create(:ci_pipeline, project: project, ref: 'master', sha: project.commit.id) }

    before do
      @success = create(:ci_build, :success, pipeline: pipeline, stage: 'build', name: 'build')
      @failed = create(:ci_build, :failed, pipeline: pipeline, stage: 'test', name: 'test', commands: 'test')
      @running = create(:ci_build, :running, pipeline: pipeline, stage: 'deploy', name: 'deploy')
      @manual = create(:ci_build, :manual, pipeline: pipeline, stage: 'deploy', name: 'manual build')
      @external = create(:generic_commit_status, status: 'success', pipeline: pipeline, name: 'jenkins', stage: 'external')
    end

    before { visit namespace_project_pipeline_path(project.namespace, project, pipeline) }

    it 'shows the pipeline graph' do
      expect(page).to have_selector('.pipeline-visualization')
      expect(page).to have_content('Build')
      expect(page).to have_content('Test')
      expect(page).to have_content('Deploy')
      expect(page).to have_content('Retry failed')
      expect(page).to have_content('Cancel running')
    end

    it 'shows Pipeline tab pane as active' do
      expect(page).to have_css('#js-tab-pipeline.active')
    end

    context 'page tabs' do
      it 'shows Pipeline and Builds tabs with link' do
        expect(page).to have_link('Pipeline')
        expect(page).to have_link('Builds')
      end

      it 'shows counter in Builds tab' do
        expect(page.find('.js-builds-counter').text).to eq(pipeline.statuses.count.to_s)
      end

      it 'shows Pipeline tab as active' do
        expect(page).to have_css('.js-pipeline-tab-link.active')
      end
    end

    context 'retrying builds' do
      it { expect(page).not_to have_content('retried') }

      context 'when retrying' do
        before { click_on 'Retry failed' }

        it { expect(page).not_to have_content('Retry failed') }
      end
    end

    context 'canceling builds' do
      it { expect(page).not_to have_selector('.ci-canceled') }

      context 'when canceling' do
        before { click_on 'Cancel running' }

        it { expect(page).not_to have_content('Cancel running') }
      end
    end
  end

  describe 'GET /:project/pipelines/:id/builds' do
    let(:project) { create(:project) }
    let(:pipeline) { create(:ci_pipeline, project: project, ref: 'master', sha: project.commit.id) }

    before do
      @success = create(:ci_build, :success, pipeline: pipeline, stage: 'build', name: 'build')
      @failed = create(:ci_build, :failed, pipeline: pipeline, stage: 'test', name: 'test', commands: 'test')
      @running = create(:ci_build, :running, pipeline: pipeline, stage: 'deploy', name: 'deploy')
      @manual = create(:ci_build, :manual, pipeline: pipeline, stage: 'deploy', name: 'manual build')
      @external = create(:generic_commit_status, status: 'success', pipeline: pipeline, name: 'jenkins', stage: 'external')
    end

    before { visit builds_namespace_project_pipeline_path(project.namespace, project, pipeline)}

    it 'shows a list of builds' do
      expect(page).to have_content('Test')
      expect(page).to have_content(@success.id)
      expect(page).to have_content('Deploy')
      expect(page).to have_content(@failed.id)
      expect(page).to have_content(@running.id)
      expect(page).to have_content(@external.id)
      expect(page).to have_content('Retry failed')
      expect(page).to have_content('Cancel running')
      expect(page).to have_link('Play')
    end

    it 'shows Builds tab pane as active' do
      expect(page).to have_css('#js-tab-builds.active')
    end

    context 'page tabs' do
      it 'shows Pipeline and Builds tabs with link' do
        expect(page).to have_link('Pipeline')
        expect(page).to have_link('Builds')
      end

      it 'shows counter in Builds tab' do
        expect(page.find('.js-builds-counter').text).to eq(pipeline.statuses.count.to_s)
      end

      it 'shows Builds tab as active' do
        expect(page).to have_css('li.js-builds-tab-link.active')
      end
    end

    context 'retrying builds' do
      it { expect(page).not_to have_content('retried') }

      context 'when retrying' do
        before { click_on 'Retry failed' }

        it { expect(page).not_to have_content('Retry failed') }
        it { expect(page).to have_selector('.retried') }
      end
    end

    context 'canceling builds' do
      it { expect(page).not_to have_selector('.ci-canceled') }

      context 'when canceling' do
        before { click_on 'Cancel running' }

        it { expect(page).not_to have_content('Cancel running') }
        it { expect(page).to have_selector('.ci-canceled') }
      end
    end

    context 'playing manual build' do
      before do
        within '.pipeline-holder' do
          click_link('Play')
        end
      end

      it { expect(@manual.reload).to be_pending }
    end
  end
end
