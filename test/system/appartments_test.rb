require "application_system_test_case"

class AppartmentsTest < ApplicationSystemTestCase
  setup do
    @appartment = appartments(:one)
  end

  test "visiting the index" do
    visit appartments_url
    assert_selector "h1", text: "Appartments"
  end

  test "creating a Appartment" do
    visit appartments_url
    click_on "New Appartment"

    click_on "Create Appartment"

    assert_text "Appartment was successfully created"
    click_on "Back"
  end

  test "updating a Appartment" do
    visit appartments_url
    click_on "Edit", match: :first

    click_on "Update Appartment"

    assert_text "Appartment was successfully updated"
    click_on "Back"
  end

  test "destroying a Appartment" do
    visit appartments_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "Appartment was successfully destroyed"
  end
end
