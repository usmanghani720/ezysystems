require 'test_helper'

class AppartmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @appartment = appartments(:one)
  end

  test "should get index" do
    get appartments_url
    assert_response :success
  end

  test "should get new" do
    get new_appartment_url
    assert_response :success
  end

  test "should create appartment" do
    assert_difference('Appartment.count') do
      post appartments_url, params: { appartment: {  } }
    end

    assert_redirected_to appartment_url(Appartment.last)
  end

  test "should show appartment" do
    get appartment_url(@appartment)
    assert_response :success
  end

  test "should get edit" do
    get edit_appartment_url(@appartment)
    assert_response :success
  end

  test "should update appartment" do
    patch appartment_url(@appartment), params: { appartment: {  } }
    assert_redirected_to appartment_url(@appartment)
  end

  test "should destroy appartment" do
    assert_difference('Appartment.count', -1) do
      delete appartment_url(@appartment)
    end

    assert_redirected_to appartments_url
  end
end
