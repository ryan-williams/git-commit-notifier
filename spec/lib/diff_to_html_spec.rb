require File.expand_path('../../spec_helper', __FILE__)
require 'diff_to_html'
require 'git'
require 'hpricot'

describe DiffToHtml do


  describe :lines_are_sequential? do
    before(:all) do
      @diff_to_html = DiffToHtml.new
    end

    it "should be true if left line numbers are sequential" do
      @diff_to_html.lines_are_sequential?({
        :added => 2,
        :removed => 2
      }, {
        :added => 3,
        :removed => 6
      }).should be_true
    end

    it "should be true if right line numbers are sequential" do
      @diff_to_html.lines_are_sequential?({
        :added => 2,
        :removed => 2
      }, {
        :added => 7,
        :removed => 3
      }).should be_true
    end

    it "should be false unless line numbers are sequential" do
      @diff_to_html.lines_are_sequential?({
        :added => 2,
        :removed => 2
      }, {
        :added => 4,
        :removed => 6
      }).should be_false
    end

    it "should be true if left line numbers are sequential (right are nil)" do
      @diff_to_html.lines_are_sequential?({
        :added => 2,
        :removed => 2
      }, {
        :added => 3,
        :removed => nil
      }).should be_true
    end

    it "should be true if right line numbers are sequential (left are nil)" do
      @diff_to_html.lines_are_sequential?({
        :added => nil,
        :removed => 2
      }, {
        :added => 7,
        :removed => 3
      }).should be_true
    end

    it "should be false unless line numbers are sequential (nils)" do
      @diff_to_html.lines_are_sequential?({
        :added => nil,
        :removed => nil
      }, {
        :added => 4,
        :removed => 6
      }).should be_false
    end
  end

  describe :unique_commits_per_branch? do
    it "should be false unless specified in config" do
      diff = DiffToHtml.new(nil, {})
      diff.should_not be_unique_commits_per_branch
    end

    it "should be false if specified as false in config" do
      diff = DiffToHtml.new(nil, { 'unique_commits_per_branch' => false })
      diff.should_not be_unique_commits_per_branch
    end

    it "should be true if specified as true in config" do
      diff = DiffToHtml.new(nil, { 'unique_commits_per_branch' => true })
      diff.should be_unique_commits_per_branch
    end
  end

  describe :get_previous_commits do
    it "should read and parse previous file if it exists" do
      fn = DiffToHtml::HANDLED_COMMITS_FILE
      diff = DiffToHtml.new
      mock(File).exists?(fn) { true }
      mock(IO).read(fn) { "a\nb" }
      diff.get_previous_commits(fn).should == %w[a b]
    end
  end

  it "multiple commits" do
    mock(Git).log(REVISIONS.first, REVISIONS.last) { IO.read(FIXTURES_PATH + 'git_log') }
    REVISIONS.each do |rev|
      mock(Git).show(rev) { IO.read(FIXTURES_PATH + 'git_show_' + rev) }
    end

    diff = DiffToHtml.new
    mock(diff).check_handled_commits(anything, 'master') { |commits, branch| commits }
    diff.diff_between_revisions REVISIONS.first, REVISIONS.last, 'testproject', 'master'

    diff.result.should have(5).commits # one result for each of the commits

    diff.result.each do |html|
      html.should_not be_include('@@') # diff correctly processed
    end

    # first commit
    hp = Hpricot diff.result.first[:html_content]
    (hp/"table").should have(2).tables # 2 files updated - one table for each of the files
    (hp/"table/tr/").each do |td|
      if td.inner_html == "require&nbsp;'iconv'"
        # first added line in changeset a4629e707d80a5769f7a71ca6ed9471015e14dc9
        td.parent.search('td')[0].inner_text.should == '' # left
        td.parent.search('td')[1].inner_text.should == '2' # right
        td.parent.search('td')[2].inner_html.should == "require&nbsp;'iconv'" # change
      end
    end

    # second commit
    hp = Hpricot diff.result[1][:html_content]
    (hp/"table").should have(1).table # 1 file updated

    # third commit - dce6ade4cdc2833b53bd600ef10f9bce83c7102d
    hp = Hpricot diff.result[2][:html_content]
    (hp/"table").should have(6).tables # 6 files updated
    (hp/"h2")[1].inner_text.should == 'Added binary file railties/doc/guides/source/images/icons/callouts/11.png'
    (hp/"h2")[2].inner_text.should == 'Deleted binary file railties/doc/guides/source/icons/up.png'
    (hp/"h2")[3].inner_text.should == 'Deleted file railties/doc/guides/source/icons/README'
    (hp/"h2")[4].inner_text.should == 'Added file railties/doc/guides/source/images/icons/README'

    # fourth commit - 51b986619d88f7ba98be7d271188785cbbb541a0
    hp = Hpricot diff.result[3][:html_content]
    (hp/"table").should have(3).tables # 3 files updated
    (hp/"table/tr/").each do |td|
      if td.inner_html =~ /create_btn/
        cols = td.parent.search('td')
        ['405', '408', ''].should be_include(cols[0].inner_text) # line 405 changed
      end
    end
  end

  it "should get good diff when new branch created" do
    first_rev, last_rev = %w[ 0000000000000000000000000000000000000000 9b15cebcc5434e27c00a4a2acea43509f9faea21 ]
    mock(Git).branch_commits('rvm') { %w[ ff037a73fc1094455e7bbf506171a3f3cf873ae6 ] }
    %w[ ff037a73fc1094455e7bbf506171a3f3cf873ae6 ].each do |rev|
      mock(Git).show(rev) { IO.read(FIXTURES_PATH + 'git_show_' + rev) }
    end
    diff = DiffToHtml.new
    mock(diff).check_handled_commits(anything, 'rvm') { |commits, branch| commits }
    diff.diff_between_revisions(first_rev, last_rev, 'tm-admin', 'rvm')
    diff.result.should have(1).commit
    hp = Hpricot diff.result.first[:html_content]
    (hp/"table").should have(1).table
    (hp/"tr.r").should have(1).row
  end
end

