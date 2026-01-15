defmodule TqfApi.AccountsTest do
  use TqfApi.DataCase

  alias TqfApi.Accounts

  describe "users" do
    alias TqfApi.Accounts.User

    import TqfApi.AccountsFixtures

    @invalid_attrs %{stripe_customer_id: nil}

    test "list_users/0 returns all users" do
      user = user_fixture()
      assert Accounts.list_users() == [user]
    end

    test "get_user!/1 returns the user with given id" do
      user = user_fixture()
      assert Accounts.get_user!(user.id) == user
    end

    test "create_user/1 with valid data creates a user" do
      valid_attrs = %{stripe_customer_id: "some stripe_customer_id"}

      assert {:ok, %User{} = user} = Accounts.create_user(valid_attrs)
      assert user.stripe_customer_id == "some stripe_customer_id"
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Accounts.create_user(@invalid_attrs)
    end

    test "update_user/2 with valid data updates the user" do
      user = user_fixture()
      update_attrs = %{stripe_customer_id: "some updated stripe_customer_id"}

      assert {:ok, %User{} = user} = Accounts.update_user(user, update_attrs)
      assert user.stripe_customer_id == "some updated stripe_customer_id"
    end

    test "update_user/2 with invalid data returns error changeset" do
      user = user_fixture()
      assert {:error, %Ecto.Changeset{}} = Accounts.update_user(user, @invalid_attrs)
      assert user == Accounts.get_user!(user.id)
    end

    test "delete_user/1 deletes the user" do
      user = user_fixture()
      assert {:ok, %User{}} = Accounts.delete_user(user)
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(user.id) end
    end

    test "change_user/1 returns a user changeset" do
      user = user_fixture()
      assert %Ecto.Changeset{} = Accounts.change_user(user)
    end
  end

  describe "devices" do
    alias TqfApi.Accounts.Device

    import TqfApi.AccountsFixtures

    @invalid_attrs %{device_uuid: nil, device_name: nil, auth_token: nil, last_seen_at: nil}

    test "list_devices/0 returns all devices" do
      device = device_fixture()
      assert Accounts.list_devices() == [device]
    end

    test "get_device!/1 returns the device with given id" do
      device = device_fixture()
      assert Accounts.get_device!(device.id) == device
    end

    test "create_device/1 with valid data creates a device" do
      valid_attrs = %{
        device_uuid: "some device_uuid",
        device_name: "some device_name",
        auth_token: "some auth_token",
        last_seen_at: ~U[2025-08-26 16:05:00Z]
      }

      assert {:ok, %Device{} = device} = Accounts.create_device(valid_attrs)
      assert device.device_uuid == "some device_uuid"
      assert device.device_name == "some device_name"
      assert device.auth_token == "some auth_token"
      assert device.last_seen_at == ~U[2025-08-26 16:05:00Z]
    end

    test "create_device/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Accounts.create_device(@invalid_attrs)
    end

    test "update_device/2 with valid data updates the device" do
      device = device_fixture()

      update_attrs = %{
        device_uuid: "some updated device_uuid",
        device_name: "some updated device_name",
        auth_token: "some updated auth_token",
        last_seen_at: ~U[2025-08-27 16:05:00Z]
      }

      assert {:ok, %Device{} = device} = Accounts.update_device(device, update_attrs)
      assert device.device_uuid == "some updated device_uuid"
      assert device.device_name == "some updated device_name"
      assert device.auth_token == "some updated auth_token"
      assert device.last_seen_at == ~U[2025-08-27 16:05:00Z]
    end

    test "update_device/2 with invalid data returns error changeset" do
      device = device_fixture()
      assert {:error, %Ecto.Changeset{}} = Accounts.update_device(device, @invalid_attrs)
      assert device == Accounts.get_device!(device.id)
    end

    test "delete_device/1 deletes the device" do
      device = device_fixture()
      assert {:ok, %Device{}} = Accounts.delete_device(device)
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_device!(device.id) end
    end

    test "change_device/1 returns a device changeset" do
      device = device_fixture()
      assert %Ecto.Changeset{} = Accounts.change_device(device)
    end
  end
end
