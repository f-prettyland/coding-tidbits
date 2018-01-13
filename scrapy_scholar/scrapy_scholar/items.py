# -*- coding: utf-8 -*-
import scrapy

class GoogleScholarItem(scrapy.Item):
    title = scrapy.Field()
    link = scrapy.Field()
    year = scrapy.Field()
    authors = scrapy.Field()
    num_of_citations = scrapy.Field()
    pass
