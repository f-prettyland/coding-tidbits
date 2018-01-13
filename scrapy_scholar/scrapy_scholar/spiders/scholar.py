# -*- coding: utf-8 -*-
import scrapy
from scrapy.exceptions import CloseSpider
import urllib.parse


class ScholarSpider(scrapy.Spider):
  name = 'scholar'
  allowed_domains = ['scholar.google.com']


  def __init__(self, category='', **kwargs):
    self.num_results = 100
    self.search = None

    # replace arguments, quit if no search term
    for key in ('search', 'num_results'):
       if key in kwargs:
         setattr(self, key, kwargs[key])
    if not self.search:
      raise CloseSpider('no_search_term')

    # add the urls to scrape for each 10 results 
    baseurl = 'https://scholar.google.com/scholar?q=' + urllib.parse.quote_plus(self.search) \
                     + '&start='
    self.start_urls = []

    for n in range(0, int(self.num_results), 10):
      self.start_urls.append(baseurl + str(n))
      
    
  def parse(self, response):
    for article in response.css("div.gs_ri"):
      title = article.css("h3.gs_rt > a.tag::text").extract_first()
      link = article.css("h3.gs_rt > a::attr(href)").extract_first()
      authors = article.css("div.gs_a a:text").extract()
      year = article.css("div.gs_a:text").extract_first()
      num_of_citations = "??"

      num_of_citations_re = article.css("div.gs_fl > a:nth-child(3)::text").extract_first()

      if len(num_of_citations_re) > 1:
        num_of_citations = num_of_citations_re[1]

      yield GoogleScholarItem(title=title, link=link, authors=authors, year=year, 
                              num_of_citations=num_of_citations)
