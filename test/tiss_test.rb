# -*- encoding : utf-8 -*-

require File.join(File.dirname(__FILE__), 'fixtures/rolle')
require File.join(File.dirname(__FILE__), 'fixtures/locked_rolle')

class TissTest < ActiveSupport::TestCase
  def test_versioning
    anzahl = Rolle.count
    
    oid1 = create_object('test').id
    oid2 = create_object('tuwien').id
    oid3 = create_object('ruby').id
    oid4 = create_object('rails').id
    oid5 = create_object('times').id
    
    assert_equal anzahl+5, Rolle.count
    
    2.upto(5) {|index| edit_object(oid1, "test" + index.to_s)}
    2.upto(7) {|index| edit_object(oid2, "tuwien" + index.to_s)}
    2.upto(9) {|index| edit_object(oid3, "ruby" + index.to_s)}
    2.upto(6) {|index| edit_object(oid4, "rails" + index.to_s)}
    2.upto(3) {|index| edit_object_with_sleep(oid5, "times" + index.to_s)}
    
    assert versions_correct?(oid1, 5)
    assert versions_correct?(oid2, 7)
    assert versions_correct?(oid3, 9)
    assert versions_correct?(oid4, 6)
    
    assert timestamps?(oid1)
    assert timestamps?(oid2)
    assert timestamps?(oid3)
    assert timestamps?(oid4)
    assert strong_timestamps?(oid5)

    destroy_record(oid2)
    assert record_unavailable_in_original_table?(oid2)
    assert deleted_record_versioned?(oid2, 8)
    
    restore_record(oid2)
    assert restored_record_available_in_original_table?(oid2)
    assert restored_record_versioned?(oid2, 9)
    
    assert save_record_without_changes(oid1)
  end
  
  def test_deleted_in_original_table
    record = create_object('test deleted_in_orginal_table')
    version_record = record.versions.find(:first)
    assert version_record != nil

    assert !version_record.deleted_in_original_table
    record.destroy

    version_record = record.find_newest_version
    assert version_record != nil
    assert version_record.version == 2
    assert version_record.deleted_in_original_table
  end

  def test_find_versions
    o = create_object("karin")
    v = o.find_versions(:all)
    assert_equal 1, v.count
    assert_equal v[0].name, "karin"

    edit_object(o.id, "zak")
    v = o.find_versions(:all)
    assert_equal 2, v.count
    assert_equal v[0].name, "karin"
    assert_equal v[1].name, "zak"

    v = o.find_versions(:all, :conditions => "name = 'zak'")
    assert_equal 1, v.count
    assert_equal v[0].name, "zak"

#    v = o.find_versions(:all, :conditions => ["name = 'zak'"])
#    assert_equal 1, v.count
#    assert_equal v[0].name, "zak"

    v = o.find_versions(:first)
    assert_equal v.name, "karin"

    v = o.find_versions(:last)
    assert_equal v.name, "zak"

    v = o.find_versions(:all, :order => "name desc")
    assert_equal 2, v.count
    assert_equal v[0].name, "zak"
    assert_equal v[1].name, "karin"
# mind the missing s

    v = o.find_version(1)
    assert_equal v.name, "karin"

    v = o.find_version(2)
    assert_equal v.name, "zak"

    assert_raises(RuntimeError) { o.find_version(3) }

    v = o.find_newest_version
    assert_equal v.name, "zak"
  end

  def test_restore
    o = create_object("lebt")
    oid = o.id
    v = o.find_version(1)
    assert v!=nil
    
    assert_raises(RuntimeError) { v.restore }
    assert !v.deleted_in_original_table
    assert !v.record_restored, "Record_restored shows that the record was undeleted (should be false) for a newly created record"

    o.destroy
    v = o.find_newest_version
    assert v.deleted_in_original_table

    v.restore
    assert !v.record_restored, "Record_restored shows that the record was undeleted (should be false) for the restored version record (but should be in the newly created record)"
    o = Rolle.find oid
    assert v.version == o.version, "Version field not restored correctly"

    v = o.find_newest_version
    assert !v.deleted_in_original_table, "Deleted_in_original_table doesn't show that the record was undeleted (should be false)"
    assert v.record_restored, "Record_restored doesn't show that the record was undeleted (should be true) for the version record created upon restore"
  end

  def test_original_record_exists
    o = create_object("lebt")
    oid = o.id
    v = o.find_version(1)
    assert v!=nil
    assert v.original_record_exists?

    o.destroy
    assert !v.original_record_exists?

    v.restore
    assert v.original_record_exists?
  end

  def test_restore_deleted
    o = create_object("lebt")
    oid = o.id
    v = o.find_version(1)
    assert v!=nil
    
    assert_raises(RuntimeError) { restore_record(oid) }
    assert !v.deleted_in_original_table

    o.destroy
    v = o.find_version(2)
    assert v!=nil
    assert v.deleted_in_original_table

    restore_record(oid)
    v = o.find_version(3)
    assert v!=nil
    assert !v.deleted_in_original_table
  end
    
  def test_restore_deleted_version
    o = create_object("lebt")
    oid = o.id
    v = o.find_version(1)
    assert v!=nil
    
    edit_object(oid, "nicht")
    x = Rolle.find(oid)
    assert x.name == "nicht"

    v = o.find_version(2)
    assert v!=nil
    o.destroy

    v = o.find_version(3)
    assert v!=nil
    assert v.deleted_in_original_table

    Rolle.restore_deleted_version(oid, 1)
    x = Rolle.find(oid)
    assert x.name == "lebt"
  end
    
  def test_destroy_unsaved_record
    o = Rolle.new(:name => "Nicht Speichern")
    assert_nothing_raised do o.destroy end
    assert_equal o.highest_version, -1
  end

  def test_versions_after_save
    r = Rolle.new(:name => 'karin')
    assert r.save
    r.name = 'zak'
    assert r.save
    assert_equal 2, r.versions.size 
    assert_equal 2, r.versions.count
  end

  def test_restore_without_validations
    r = Rolle.new(:name => 'karin')
    assert r.save
    version = r.find_newest_version
    r.destroy
    
    r = Rolle.new(:name => 'karin')
    assert r.save
    
    assert_raises RuntimeError do version.restore end
    assert_nothing_raised do version.restore(perform_validations = false) end
  end

  def test_save_without_revision
    r = Rolle.new(:name => 'karin')
    assert_equal true, r.save_without_revision
    
    r = Rolle.new(:name => 'karin')
    assert_equal false, r.save_without_revision
  end

=begin
# Wait until experimenting-with-optimistic-locking is merged.
  def test_locked_rolle
    r = LockedRolle.new(:name => 'karin')
    r.save
    assert_equal 1, r.find_newest_version.version
    r.name = 'zak'
    r.save
    assert_equal 2, r.find_newest_version.version
    # assert_equal 1, r.version # currently we only create a version record with the correct version, the version field in the original model is not update, since that seems to break other things.
    assert_equal 2, r.version # currently we only create a version record with the correct version, the version field in the original model is not update, since that seems to break other things.
    r2 = LockedRolle.find r.id
    assert_equal 2, r2.version
  end

  def test_locked_rolle2
# not needed any more
    r = LockedRolle.new(:name => 'karin')
    r.save
    assert_equal 0, r.find_newest_version.lock_version
    r.name = 'zak'
    r.save
    assert_equal 0, r.find_newest_version.lock_version
  end
=end

private
  def create_object(bezeichnung)
    o = Rolle.new(:name => bezeichnung)
    o.save
    return o
  end
  
  def edit_object(id, bezeichnung)
    Rolle.find(id).update_attributes(:name=>bezeichnung)
  end

  def edit_object_with_sleep(id, bezeichnung)
    sleep(2)
    Rolle.find(id).update_attributes(:name=>bezeichnung)
  end

  def versions_correct?(id, highest_version)
    result = Rolle.find(id).versions.find(:all).size == highest_version
    1.upto(highest_version) do |current_version|
      current_version_record = Rolle.find(id).versions.find(:first, :conditions => "version = #{current_version}")
      result = false if current_version_record.nil? || current_version_record.deleted_in_original_table == true
    end
    return result
  end
 
  def timestamps?(id)
    result = true;
    highest_version = Rolle.find(id).versions.find(:all).size
    highest_version.downto(1) do |current_version|
      if current_version >= 2
        rolle_current_version = Rolle.find(id).versions.find(:first, :conditions => "version = #{current_version}")
        rolle_predecessor_version = Rolle.find(id).versions.find(:first, :conditions => "version = #{current_version-1}")
        toleranz = rolle_current_version.created_at - rolle_predecessor_version.updated_at
        result = false if toleranz > 1.0
      end
    end
    return result
  end
  
  def strong_timestamps?(id)
    result = true;
    highest_version = Rolle.find(id).versions.find(:all).size
    highest_version.downto(2) do |current_version|
      rolle_current_version = Rolle.find(id).versions.find(:first, :conditions => "version = #{current_version}")
      rolle_predecessor_version = Rolle.find(id).versions.find(:first, :conditions => "version = #{current_version-1}")
      result = false unless rolle_current_version.created_at = rolle_predecessor_version.updated_at
      result = false unless rolle_current_version.created_at >= rolle_predecessor_version.created_at
    end
    return result
  end

  def destroy_record(id)
    # Rolle.destroy(id)
    Rolle.destroy(id)
  end
  
  def record_unavailable_in_original_table?(id)
    begin
      Rolle.find(id)
      return false
    rescue
      return true
    end
  end
  
  def deleted_record_versioned?(id, highest_version)
    version_of_deleted_record = highest_version
    rolle_deleted = Rolle::Version.find(:first, :conditions => "version = #{version_of_deleted_record} and rolle_id = #{id}")
    return rolle_deleted != nil && rolle_deleted.deleted_in_original_table == true
  end
  
  def restore_record(id)
    Rolle.restore_deleted(id)
  end
  
  def restored_record_available_in_original_table?(id)
    begin
      Rolle.find(id)
      return true
    rescue
      return false
    end
  end
  
  def restored_record_versioned?(id, highest_version)
    version_of_restored_record = highest_version
    rolle_restored = Rolle.find(id).versions.find(:first, :conditions => "version = #{version_of_restored_record}")
    return rolle_restored != nil && rolle_restored.deleted_in_original_table == false
  end
  
  def save_record_without_changes(id)
    versions_before_save = Rolle.find(id).versions.find(:all).size
    rolle = Rolle.find(id)
    rolle.update_attributes(:name=>rolle.name)
    versions_after_save = Rolle.find(id).versions.find(:all).size
    return versions_before_save == versions_after_save
  end
  
end
