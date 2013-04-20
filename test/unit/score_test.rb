require 'test_helper'

class ScoreTest < ActiveSupport::TestCase
  def score_helper(leaderboard, user, value, created_at = nil)
    s = leaderboard.scores.build()
    s.value = value
    s.user_id = user.id if user.is_a?(User)
    s.user_id = user if user.is_a?(Fixnum)
    s.created_at = created_at if created_at
    s
  end

  def score_helper!(*args)
    s = score_helper(*args)
    if !s.save
      raise StandardError.new("Score helper fail.")
    end
    s
  end


  def scores(leaderboard, user)
    Score.where(leaderboard_id: leaderboard.id, user_id: user.id)
  end

  def setup
    @hs_leaderboard = Leaderboard.create!(name: "high", sort_type: Leaderboard::HIGH_VALUE_SORT_TYPE)
    @ls_leaderboard = Leaderboard.create!(name: "low", sort_type: Leaderboard::LOW_VALUE_SORT_TYPE)
    @user   = User.create!(nick: "foo")
    @user2  = User.create!(nick: "bar")
  end

  test "scores of the same leaderboard type should compare properly" do
    s1 = score_helper(@hs_leaderboard, @user, 150)
    s2 = score_helper(@hs_leaderboard, @user, 100)
    assert s1.is_better_than?(s2), "High score comparison is broken"

    s3 = score_helper(@ls_leaderboard, @user, 150)
    s4 = score_helper(@ls_leaderboard, @user, 100)
    assert !s3.is_better_than?(s4), "Low score comparison is broken"

    s5 = score_helper(@ls_leaderboard, @user, 100)
    assert !s4.is_better_than?(s5)
  end


  test "scores only post to the appropriate Best tables" do
    score_helper(@hs_leaderboard, @user, 50, Time.now - 1.minutes).save
    score_helper(@hs_leaderboard, @user, 100, Time.now - 2.days).save
    score_helper(@hs_leaderboard, @user, 150, Time.now - 2.weeks).save

    # Now let's create a new score of 75.
    s1 = score_helper(@hs_leaderboard, @user, 75).save

    assert_equal 75,  Score.best_for('today', @hs_leaderboard.id, @user.id).value
    assert_equal 100, Score.best_for('this_week', @hs_leaderboard.id, @user.id).value
    assert_equal 150, Score.best_for('all_time', @hs_leaderboard.id, @user.id).value

    # Now let's create a new score of 125.
    s2 = score_helper(@hs_leaderboard, @user, 125).save

    assert_equal 125,  Score.best_for('today', @hs_leaderboard.id, @user.id).value
    assert_equal 125, Score.best_for('this_week', @hs_leaderboard.id, @user.id).value
    assert_equal 150, Score.best_for('all_time', @hs_leaderboard.id, @user.id).value

    # Now 200
    s3 = score_helper(@hs_leaderboard, @user, 200).save

    assert_equal 200,  Score.best_for('today', @hs_leaderboard.id, @user.id).value
    assert_equal 200, Score.best_for('this_week', @hs_leaderboard.id, @user.id).value
    assert_equal 200, Score.best_for('all_time', @hs_leaderboard.id, @user.id).value
  end

  test "scores should be saved in utc" do
    score = score_helper(@hs_leaderboard, @user, 100)
    score.created_at = Time.parse("2013-03-23 15:00:00 -0700")
    score.save
    created_at_str = Score.find_by_id(score.id).attributes_before_type_cast["created_at"].to_s
    assert "2013-03-23 22:00:00 UTC", created_at_str
  end

  test "high score best" do
    s1 = score_helper(@hs_leaderboard, @user, 100).save
    assert_equal 100, Score.best_for('today', @hs_leaderboard.id, @user.id).value

    s2 = score_helper(@hs_leaderboard, @user, 200).save
    assert_equal 200, Score.best_for('today', @hs_leaderboard.id, @user.id).value
  end

  test "low score best" do
    s1 = score_helper(@ls_leaderboard, @user, 100).save

    assert_equal 100, Score.best_for('today', @ls_leaderboard.id, @user.id).value

    s2 = score_helper(@ls_leaderboard, @user, 200).save
    assert_equal 100, Score.best_for('today', @ls_leaderboard.id, @user.id).value

    s3 = score_helper(@ls_leaderboard, @user, 50).save
    assert_equal 50, Score.best_for('today', @ls_leaderboard.id, @user.id).value
  end

  test "a user should only have one best score for any time range" do
    score_helper(@hs_leaderboard, @user, 100).save
    score_helper(@hs_leaderboard, @user, 300).save
    assert_equal 1, Score.bests_for('today', @hs_leaderboard.id).count

    score_helper(@hs_leaderboard, @user2, 100).save
    assert_equal 2, Score.bests_for('today', @hs_leaderboard.id).count
  end

  test "a best score moving out of range" do
    s1 = score_helper!(@hs_leaderboard, @user, 100, Time.now)
    s2 = score_helper!(@hs_leaderboard, @user, 50, Time.now)
    assert_equal 1,   Score.bests_for('this_week', @hs_leaderboard.id).count
    assert_equal 100, Score.bests_for('this_week', @hs_leaderboard.id)[0].value

    s1.update_attributes({:created_at => Time.now - 7.days - 1.second}, :without_protection => true)
    assert_equal 1, Score.bests_for('this_week', @hs_leaderboard.id).count
    assert_equal 50, Score.bests_for('this_week', @hs_leaderboard.id)[0].value
  end

  test "high score rank" do
    s1 = score_helper!(@hs_leaderboard, @user, 100, Time.now)
    s2 = score_helper!(@hs_leaderboard, @user2, 50, Time.now)
    assert_equal 1, Score.best_for('this_week', @hs_leaderboard.id, @user.id).rank
    assert_equal 2, Score.best_for('this_week', @hs_leaderboard.id, @user2.id).rank

    s1.update_attributes({:created_at => Time.now - 8.days}, :without_protection => true)
    assert_nil        Score.best_for('this_week', @hs_leaderboard.id, @user.id)
    assert_equal 1,   Score.best_for('this_week', @hs_leaderboard.id, @user2.id).rank
  end

  test "low score rank" do
    s1 = score_helper!(@ls_leaderboard, @user, 4, Time.now)
    s2 = score_helper!(@ls_leaderboard, @user2, 5, Time.now)
    assert_equal 1, Score.best_for('this_week', @ls_leaderboard.id, @user.id).rank
    assert_equal 2, Score.best_for('this_week', @ls_leaderboard.id, @user2.id).rank

    s1.update_attributes({:created_at => Time.now - 8.days}, :without_protection => true)
    assert_nil        Score.best_for('this_week', @ls_leaderboard.id, @user.id)
    assert_equal 1,   Score.best_for('this_week', @ls_leaderboard.id, @user2.id).rank
  end
  
end
