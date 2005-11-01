require File.dirname(__FILE__) + '/test_helper'

class TranslationTest < Test::Unit::TestCase
  fixtures :translations, :products, :categories, :categories_products

  class Product < ActiveRecord::Base
    has_and_belongs_to_many :categories
    belongs_to :manufacturer

    translates :name, :description, :specs
  end

  class Category < ActiveRecord::Base
    has_and_belongs_to_many :products

    translates :name
  end

  class Manufacturer < ActiveRecord::Base
    has_many :products

    translates :name  
  end

  def setup
    Language.active_language_code = 'en'
  end

  def test_prod_tr_all
    prods = Product.find(:all, :order => "code" )
    assert_equal 2, prods.length
    assert_equal "first-product", prods[0].code 
    assert_equal "second-product", prods[1].code 
    assert_equal "these are the specs for the first product",
      prods[0].specs    
    assert_equal "This is a description of the first product",
      prods[0].description    
    assert_equal "these are the specs for the second product",
      prods[1].specs
  end

  def test_prod_tr_first
    prod = Product.find(:first)
    assert_equal "first-product", prod.code 
    assert_equal "these are the specs for the first product",
      prod.specs    
    assert_equal "This is a description of the first product",
      prod.description    
  end

  def test_prod_tr_id
    prod = Product.find(1)
    assert_equal "first-product", prod.code 
    assert_equal "these are the specs for the first product",
      prod.specs    
    assert_equal "This is a description of the first product",
      prod.description    
  end

  def test_prod_tr_ids
    prods = Product.find(1, 2)
    assert_equal 2, prods.length
    assert_equal "first-product", prods[0].code 
    assert_equal "second-product", prods[1].code 
    assert_equal "these are the specs for the first product",
      prods[0].specs    
    assert_equal "This is a description of the first product",
      prods[0].description    
    assert_equal "these are the specs for the second product",
      prods[1].specs
  end

  def test_base
    Language.active_language_code = 'he'
    prod = Product.find(1)
    assert_equal "first-product", prod.code 
    assert_equal "these are the specs for the first product",
      prod.specs    
    assert_equal "זהו תיאור המוצר הראשון",
      prod.description    
  end

  def test_habtm_translation
    cat = Category.find(1)
    prods = cat.products
    assert_equal 1, prods.length
    prod = prods.first
    assert_equal "first-product", prod.code 
    assert_equal "these are the specs for the first product",
      prod.specs    
    assert_equal "This is a description of the first product",
      prod.description        
  end

  # test has_many translation

  # test belongs_to translation

  def test_new
    prod = Product.new(:code => "new-product", :specs => "These are the product specs")
    assert_equal "These are the product specs", prod.specs
    assert_nil prod.description
  end

  # test creating updating
  def test_create_update
    prod = Product.create(:code => "new-product", 
      :specs => "These are the product specs")
    assert prod.errors.empty?, prod.errors.full_messages.first
    prod = nil
    prod = Product.find_by_code("new-product")
    assert_not_nil prod
    assert_equal "These are the product specs", prod.specs

    prod.specs = "Dummy"
    prod.save
    prod = nil
    prod = Product.find_by_code("new-product")
    assert_not_nil prod
    assert_equal "Dummy", prod.specs
  end

  # other association stuff? building?

end
