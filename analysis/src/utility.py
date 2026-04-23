import json
import pandas as pd
import os
import numpy as np
import matplotlib.pyplot as plt
import ast
import glob
import calendar
import warnings
import time
import datetime as datetime

def load_eue_shortfall(area_code_region, scenario, IDIR):
    
    df = pd.read_csv(os.path.join(IDIR, scenario, "shortfall_eue.csv"))
    df['timestamp'] = pd.to_datetime(df['timestamp'])
    df = df.set_index('timestamp')
    string_key_dict = {str(key): value for key, value in area_code_region.items()}
    df.columns = df.columns.map(string_key_dict)
    return df


def reg_load_gen(shortfall_data):
    region_gens = {}
    region_load = {}
    region_storage = {}
    timestamp = shortfall_data["timestamps"]
    timestamp = pd.to_datetime(timestamp, utc=True)
    area_code_region = {1:"NNSW", 2:"CNSW", 3:"SNW", 4:"SNSW", 5:"WNV",
                        6:"MEL", 7:"SEV",  8:"NQ", 9:"CQ", 10:"GG",
                        11:"SQ", 12:"NSA", 13:"CSA", 14:"SESA", 15:"TAS"}
    for i, cap in enumerate(shortfall_data['region_results']):
        reg = area_code_region[int(cap["name"])]
        region_storage[reg] =  pd.DataFrame(cap['capacity']['Battery'])
        all_cap = pd.DataFrame(cap['capacity'])
        del all_cap['Battery']
        region_gens[reg] =  pd.DataFrame(all_cap['capacity'])
        region_load[reg] =  pd.DataFrame(cap['load'])
    
    for kk, vv in region_gens.items():
        region_gens[kk] = pd.DataFrame(region_gens[kk])
        region_gens[kk]["timestamp"] = timestamp
        region_gens[kk] = region_gens[kk].set_index('timestamp')
        region_gens[kk]["total_gen"] = region_gens[kk].sum(axis=1)

    for kk, vv in region_storage.items():
        region_storage[kk] = pd.DataFrame(region_storage[kk])
        region_storage[kk]["timestamp"] = timestamp
        region_storage[kk] = region_storage[kk].set_index('timestamp')
        region_storage[kk]["total_storage"] = region_storage[kk].sum(axis=1)
    
    for kk, vv in region_load.items():
        vv = pd.DataFrame(vv)
        region_load[kk]["timestamp"] = timestamp
        region_load[kk] = region_load[kk].set_index('timestamp')
        region_load[kk]["total_gen"] = region_gens[kk]["total_gen"]
        region_load[kk]["total_storage"] = region_storage[kk]["total_storage"]
        region_load[kk] = region_load[kk].rename(columns={0:"load"})
    return region_load



def get_rel_data(shortfall_data, flow_for, storage, target_region, flow_name, st_date, en_date, area_code_region):
    found_key = next((key for key, value in area_code_region.items() if value == target_region), None)
    #st = storage[storage.index.month==1]
    st = storage[(storage.index > st_date) & (storage.index < en_date)]
    st_data = st.reset_index()
    file_path = os.path.join(os.getcwd(), '../data', 'sc_data', "future_storage_pp.csv")
    bat_data = pd.read_csv(file_path)
    bat_dev_list = bat_data[bat_data.area == found_key].name.unique().tolist()
    
    colors = ["green",'#30D5C8',"brown"]
    styles = ['','','x','*']

    fr = flow_for[flow_name].copy()
    fr = pd.DataFrame(fr.abs())
    fr = fr[(fr.index > st_date) & (fr.index < en_date)].reset_index()
    index = -1
    for inx, i in enumerate(shortfall_data["region_results"]):
        if i["name"] == str(found_key):
            index = inx
            break

    csa_load_gen = extract_load_gen_case_study(shortfall_data, index, bat_dev_list)
    csa_load_gen = csa_load_gen[(csa_load_gen.index > st_date) & (csa_load_gen.index < en_date)]
    csa_load_gen = csa_load_gen.reset_index()

    comb = fr.merge(csa_load_gen, on='timestamp')
    comb.timestamp = comb.timestamp.dt.tz_localize(None)
    
    comb = comb.merge(st_data, on='timestamp')
    comb_2 = None
    if len(bat_dev_list) > 0:
        comb["agg_bat"] = comb[bat_dev_list].sum(axis=1)
        comb_1 = comb[['timestamp', flow_name, 'load', 'tot_gen', 'agg_bat']]
        comb2 = comb.set_index('timestamp')
        comb_2 = comb2[bat_dev_list]
    else:
        comb_1 = comb[['timestamp', flow_name, 'load', 'tot_gen']]
    comb_1 = comb_1.set_index('timestamp')
    return comb_1, comb_2


def reg_load_gen(shortfall_data):
    region_gens = {}
    region_load = {}
    timestamp = shortfall_data["timestamps"]
    timestamp = pd.to_datetime(timestamp, utc=True)
    area_code_region = {1:"NNSW", 2:"CNSW", 3:"SNW", 4:"SNSW", 5:"WNV",
                        6:"MEL", 7:"SEV",  8:"NQ", 9:"CQ", 10:"GG",
                        11:"SQ", 12:"NSA", 13:"CSA", 14:"SESA", 15:"TAS"}
    for i, cap in enumerate(shortfall_data['region_results']):
        reg = area_code_region[int(cap["name"])]
        region_gens[reg] =  pd.DataFrame(cap['capacity'])
        region_load[reg] =  pd.DataFrame(cap['load'])
    
    for kk, vv in region_gens.items():
        region_gens[kk] = pd.DataFrame(region_gens[kk])
        region_gens[kk]["timestamp"] = timestamp
        region_gens[kk] = region_gens[kk].set_index('timestamp')
        region_gens[kk]["total_gen"] = region_gens[kk].sum(axis=1)
    
    for kk, vv in region_load.items():
        vv = pd.DataFrame(vv)
        region_load[kk]["timestamp"] = timestamp
        region_load[kk] = region_load[kk].set_index('timestamp')
        region_load[kk]["total_gen"] = region_gens[kk]["total_gen"]
        region_load[kk] = region_load[kk].rename(columns={0:"load"})
    return region_load

def load_gen_summary(region_load):
    figsize = (20,10)
    demand_zones ={'NSW':['CNSW', 'NNSW', 'SNSW', 'SNW'],
              'QLD':['CQ', 'GG', 'NQ', 'SQ'],
               'SA':['NSA', 'CSA', 'SESA'],
               'VIC':['WNV', 'MEL', 'SEV'],
               'TAS':['TAS']}
    def find_key(target_value, my_dict):
        for key, value in my_dict.items():
            if target_value in value:
               return key

    fig, axes_1 = plt.subplots(figsize=figsize, nrows=1, ncols=1)
    fig, axes = plt.subplots(figsize=figsize, nrows=2, ncols=4)
    fig, axes_2 = plt.subplots(figsize=figsize, nrows=2, ncols=3)
    
    plt.subplots_adjust(wspace=0, hspace=0)
    region_list = ["NSW","QLD","VIC","SA","TAS"]
    cnt1 = 0
    cnt2 = 0
    cnt3 = 0
    cnt4 = 0
    color = ['purple','#30D5C8']  # Turquoise for generation
    for kk,vv in region_load.items():
        region = find_key(kk, demand_zones)
        if region == region_list[0]:
            vv.plot(ax=axes[0, cnt1],color=color, title=kk,legend=False)
            axes[0, cnt1].tick_params(axis='x', labelrotation=45)
            axes[0, cnt1].set_xlabel('') 
            cnt1 += 1
        elif region == region_list[1]:
            vv.plot(ax=axes[1, cnt2],color=color, title=kk, legend=False)
            axes[1, cnt2].tick_params(axis='x', labelrotation=45)
            axes[1, cnt2].set_xlabel('')
            cnt2 += 1
        elif region == region_list[2]:
            vv.plot(ax=axes_2[0, cnt3],color=color, title=kk, legend=False)
            axes_2[0, cnt3].tick_params(axis='x', labelrotation=45)
            axes_2[0, cnt3].set_xlabel('')
            cnt3 += 1
        elif region == region_list[3]:
            vv.plot(ax=axes_2[1, cnt4],color=color, title=kk, legend=False)
            axes_2[1, cnt4].tick_params(axis='x', labelrotation=45)
            axes_2[1, cnt4].set_xlabel('')
            cnt4 += 1
        elif region == region_list[4]:
            vv.plot(ax=axes_1,color=color, title=kk)
            axes_1.tick_params(axis='x', labelrotation=45)
            axes_1.set_xlabel('')


def plot_shortfall_eue(df):
    markers = ['s','o', 'D', 'P', '^','*','v','>','1','+','','','','','','']
    figsize = (30,8)
    fig, axes = plt.subplots(figsize=figsize, nrows=1, ncols=1)
    for i, cols in enumerate(df.columns):
        df[cols].plot(ax=axes, marker=markers[i],legend=True)
    axes.grid()

def mean_shortfall_period(sd, timestamps, area_code_region, eue_df):
    figsize = (20,4)
    demand_zones ={'NSW':['CNSW', 'NNSW', 'SNSW', 'SNW'],
              'QLD':['CQ', 'GG', 'NQ', 'SQ'],
               'SA':['NSA', 'CSA', 'SESA'],
               'VIC':['WNV', 'MEL', 'SEV'],
               'TAS':['TAS']}
    def find_key(target_value, my_dict):
        for key, value in my_dict.items():
            if target_value in value:
               return key
 
    region_list = ["NSW","QLD","VIC","SA","TAS"]
    
    for vv in sd:
        sub_region = area_code_region[int(vv["name"])]
        region = find_key(sub_region, demand_zones)
        title = "Shortfall mean for " + sub_region
        title2 = "EUE values with LOLE = 1 instances \n where that hour had a shortfall in every MC sample"  
        if region == region_list[0] and len(vv["shortfall_timestamps"]) > 0:
            
            sf = pd.DataFrame({"timestamp":timestamps, 
              "shortfall_mean":vv["shortfall_mean"]})
            sf = sf.set_index('timestamp')
            fig, (ax1,ax2) = plt.subplots(figsize=figsize, nrows=1, ncols=2)
            sf.plot(ax=ax1, title=title,legend=False)
            eue_df.reset_index().plot.scatter(x='timestamp', y=sub_region, ax=ax2, title=title2, color='r',marker="*")
            plt.tight_layout()
            ax1.grid()
            ax2.grid()
            
        elif region == region_list[1] and len(vv["shortfall_timestamps"]) > 0:
            
            sf = pd.DataFrame({"timestamp":timestamps, 
              "shortfall_mean":vv["shortfall_mean"]})
            sf = sf.set_index('timestamp')
            fig, (ax1,ax2) = plt.subplots(figsize=figsize, nrows=1, ncols=2)
            sf.plot(ax=ax1, title=title,legend=False)
            eue_df.reset_index().plot.scatter(x='timestamp', y=sub_region, ax=ax2, title=title2, color='r',marker="*")
            plt.tight_layout()
            ax1.grid()
            ax2.grid()
            
        elif region == region_list[2] and len(vv["shortfall_timestamps"]) > 0:
            
            sf = pd.DataFrame({"timestamp":timestamps, 
              "shortfall_mean":vv["shortfall_mean"]})
            sf = sf.set_index('timestamp')
            fig, (ax1,ax2) = plt.subplots(figsize=figsize, nrows=1, ncols=2)
            sf.plot(ax=ax1, title=title,legend=False)
            eue_df.reset_index().plot.scatter(x='timestamp', y=sub_region, ax=ax2, title=title2, color='r',marker="*")
            plt.tight_layout()
            ax1.grid()
            ax2.grid()
            
            
        elif region == region_list[3] and len(vv["shortfall_timestamps"]) > 0:
            
            sf = pd.DataFrame({"timestamp":timestamps, 
              "shortfall_mean":vv["shortfall_mean"]})
            sf = sf.set_index('timestamp')
            fig, (ax1,ax2) = plt.subplots(figsize=figsize, nrows=1, ncols=2)
            sf.plot(ax=ax1, title=title,legend=False)
            eue_df.reset_index().plot.scatter(x='timestamp', y=sub_region, ax=ax2, title=title2, color='r',marker="*")
            plt.tight_layout()
            ax1.grid()
            ax2.grid()
            
        elif region == region_list[4] and len(vv["shortfall_timestamps"]) > 0:
            
            sf = pd.DataFrame({"timestamp":timestamps, 
              "shortfall_mean":vv["shortfall_mean"]})
            sf = sf.set_index('timestamp')
            fig, (ax1,ax2) = plt.subplots(figsize=figsize, nrows=1, ncols=2)
            sf.plot(ax=ax1, title=title,legend=False)
            eue_df.reset_index().plot.scatter(x='timestamp', y=sub_region, ax=ax2, title=title2, color='r',marker="*")
            plt.tight_layout()
            ax1.grid()
            ax2.grid()

def flow_result(scenario, area_code_region, IDIR):
    flow_file_name = os.path.join(IDIR, scenario, "pras_flow_timeseries.csv")
    pras_flow = pd.read_csv(flow_file_name)
    pras_flow['timestamp'] = pd.to_datetime(pras_flow['timestamp'], utc=True)
    pras_flow = pras_flow.set_index('timestamp')
    flow_for, std_flow = util_flow(pras_flow, area_code_region)
    return flow_for

def extract_load_gen_case_study(shortfall_data, index, bat_dev_list):
    
    nsa_load = shortfall_data["region_results"][index]["load"]
    timestamp = shortfall_data["timestamps"]
    nsa_load = pd.DataFrame(nsa_load)
    nsa_load.index = timestamp
    nsa_load.index = pd.to_datetime(nsa_load.index, utc=True)
    nsa_gen_cap = shortfall_data["region_results"][index]["capacity"]
   
    nsa_gen_cap = pd.DataFrame(nsa_gen_cap)
    nsa_gen_cap.index = timestamp
    nsa_gen_cap.index = pd.to_datetime(nsa_gen_cap.index, utc=True)
    if len(bat_dev_list) > 0:
        del nsa_gen_cap['Battery']
    nsa_gen_cap['tot_gen'] = nsa_gen_cap.sum(axis=1)
    nsa_gen_cap = pd.DataFrame(nsa_gen_cap['tot_gen'])
    nsa_load = nsa_load.rename(columns={0:"load"})
    nsa_load_gen = nsa_load.merge(nsa_gen_cap, on=nsa_load.index)
    nsa_load_gen = nsa_load_gen.rename(columns={'key_0': 'timestamp'})
    nsa_load_gen = nsa_load_gen.set_index('timestamp')
    return nsa_load_gen

def find_max_eue_regions(area_code_region, eue_df):
    unserv_en_dict = {}
    for kk in area_code_region.values():
        nsa = pd.DataFrame(eue_df[kk]).reset_index()
        nsa_jan = nsa[nsa.timestamp.dt.month==1]
        nsa_jan = nsa_jan[(nsa_jan.timestamp > st_date) & (nsa_jan.timestamp < en_date)]
        if nsa_jan[kk].max() > 0:
            unserv_en_dict[kk] = nsa_jan[kk].max()
    max_EUE = pd.DataFrame([unserv_en_dict])   
    return max_EUE

def plot_special_case(flow_for):
 
    figsize = (25,10)
    fig, axes = plt.subplots(figsize=figsize, nrows=3, ncols=5)
    #plt.subplots_adjust(wspace=0, hspace=0)
    fig.suptitle("Daily Average flow")
    flow_for.columns = flow_for.columns.str.replace('_mean_flow', '')
    x = 0
    y = 0
    for i, col in enumerate(flow_for.columns.tolist()):
        if i == 5 :
            x = 1
            y = 0
        if i == 10 :
            x = 2
            y = 0
        flow_for[col].plot(legend=True, ax=axes[x,y])
        #axes[x,y].set_xlabel("")
        #axes[x,y].set_xticks([]) 
        axes[x,y].tick_params(axis='x', labelrotation=45)
        axes[x,y].set_xlabel('') 
        if x != 2:
            axes[x,y].set_xticks([])
            
        y += 1

def get_reg_load_gen(shortfall_data):
    region_gens = {}
    region_load = {}
    timestamp = shortfall_data["timestamps"]
    area_code_region = {1:"NNSW", 2:"CNSW", 3:"SNW", 4:"SNSW", 5:"WNV",
                        6:"MEL", 7:"SEV",  8:"NQ", 9:"CQ", 10:"GG",
                        11:"SQ", 12:"NSA", 13:"CSA", 14:"SESA", 15:"TAS"}
    for i, cap in enumerate(shortfall_data['region_results']):
        reg = area_code_region[int(cap["name"])]
        region_gens[reg] =  pd.DataFrame(cap['capacity'])
        region_load[reg] =  pd.DataFrame(cap['load'])
    
    for kk, vv in region_gens.items():
        region_gens[kk] = pd.DataFrame(region_gens[kk])
        region_gens[kk]["timestamp"] = pd.to_datetime(timestamp)
        region_gens[kk] = region_gens[kk].set_index('timestamp')
    return region_load, region_gens


def set_bold(ax1):
    for label in ax1.get_xticklabels():
        label.set_fontweight('bold')
    for label in ax1.get_yticklabels():
        label.set_fontweight('bold')
    ax1.set_ylabel("NEUE", fontweight='bold', fontsize=14)
    
    ax1.legend(prop={'weight': 'bold'}, reverse=True)  
    return ax1


def seasonal_ppmm_stats(shortfall_data, area_code_region, 
                        scenario, IDIR, figsize):
    summer_months = [12, 1, 2]  
    spring_months = [9, 10, 11]
    winter_months = [6, 7, 8] 
    autumn_months = [3, 4, 5]
    colors = [
            'red', 'blue', 'green', 'purple', 'orange',
            'cyan', 'magenta', 'lime', 'pink', 'teal',
            'brown', 'gray', 'olive', 'navy', 'gold'
        ]
    region_map = {"NNSW":"NSW", "CNSW":"NSW", "SNW":"NSW", "SNSW":"NSW", "WNV":"VIC",
                    "MEL":"VIC", "SEV":"VIC",  "NQ":"QLD", "CQ":"QLD", "GG":"QLD",
                    "SQ":"QLD", "NSA":"SA", "CSA":"SA", "SESA":"SA", "TAS":"TAS"}
    df = load_eue_shortfall(area_code_region, scenario, IDIR)
    df['season'] = len(df) * [""]
    df.loc[df.index.month.isin(summer_months), "season"] = "summer"
    df.loc[df.index.month.isin(spring_months), "season"] = "spring"
    df.loc[df.index.month.isin(winter_months), "season"] = "winter"
    df.loc[df.index.month.isin(autumn_months), "season"] = "autumn"
    custom_category =["summer", "autumn", "winter", "spring"]

    seasonal_data = df.groupby([df.index.year, "season"]).sum().reset_index()
    seasonal_data['season'] = pd.Categorical(seasonal_data['season'], categories=custom_category, ordered=True)
    seasonal_data = seasonal_data.sort_values(by=['timestamp', 'season'])
    seasonal_data = seasonal_data.set_index(['timestamp', 'season'])
    seasonal_data['NSW'] = seasonal_data['NNSW'] + seasonal_data['CNSW'] + seasonal_data['SNW'] + seasonal_data['SNSW']
    seasonal_data['VIC'] = seasonal_data['WNV'] + seasonal_data['MEL'] + seasonal_data['SEV']
    seasonal_data['QLD']= seasonal_data['NQ'] + seasonal_data['CQ'] + seasonal_data['GG'] + seasonal_data['SQ']
    seasonal_data['SA'] = seasonal_data['NSA'] + seasonal_data['CSA'] + seasonal_data['SESA']
    load_data = pd.DataFrame()
    for i, cap in enumerate(shortfall_data['region_results']):
        reg = area_code_region[int(cap["name"])]
        load_data[reg] = cap['load']
    if "LT" in scenario:
        freq = "60min"
    else:
        freq = "30min"
    
    full_range = pd.date_range(start=df.index.min(), end=df.index.max(), freq=freq)
    df = df.reindex(full_range, fill_value=0)
    df.index.name = "timestamp"
    load_data = load_data.set_index(df.index)
    load_data.loc[load_data.index.month.isin(summer_months), "season"] = "summer"
    load_data.loc[load_data.index.month.isin(spring_months), "season"] = "spring"
    load_data.loc[load_data.index.month.isin(winter_months), "season"] = "winter"
    load_data.loc[load_data.index.month.isin(autumn_months), "season"] = "autumn"
    custom_category =["summer", "autumn", "winter", "spring"]
   
    seasonal_data_load = load_data.groupby([load_data.index.year, "season"]).sum().reset_index()
    seasonal_data_load['season'] = pd.Categorical(seasonal_data_load['season'], categories=custom_category, ordered=True)
    seasonal_data_load = seasonal_data_load.sort_values(by=['timestamp', 'season'])
    seasonal_data_load = seasonal_data_load.set_index(['timestamp', 'season'])
    seasonal_data_load['NSW'] = seasonal_data_load['NNSW'] + seasonal_data_load['CNSW'] + seasonal_data_load['SNW'] + seasonal_data_load['SNSW']
    seasonal_data_load['VIC'] = seasonal_data_load['WNV'] + seasonal_data_load['MEL'] + seasonal_data_load['SEV']
    seasonal_data_load['QLD'] = seasonal_data_load['NQ'] + seasonal_data_load['CQ'] + seasonal_data_load['GG'] + seasonal_data_load['SQ']
    seasonal_data_load['SA'] = seasonal_data_load['NSA'] + seasonal_data_load['CSA'] + seasonal_data_load['SESA']

    fig, ax1 = plt.subplots(figsize=figsize, nrows=1, ncols=1)
    seasonal_data = seasonal_data/seasonal_data_load
    
    seasonal_data[region_map.keys()].plot.area(ax=ax1, color=colors)
    ax1.set_xticks(list(range(0, len(seasonal_data))), labels=seasonal_data.index.tolist())
    ax1.set_xticklabels(seasonal_data.index.tolist(), fontweight='bold',
                        fontsize=14,
                        rotation=45, ha='right')
    ax1.set_xlabel('')
    ax1 = set_bold(ax1)
    title = "Seasonal NEUE Metrics for scenario: " + scenario + "\n for all areas"
    ax1.set_title(title, weight="bold", fontsize=15)
    ax1.grid()
    
    return seasonal_data
    
    
def get_data_simu(shortfall_data):
    load_gens_simu = {} 
    region_load, region_gens = get_reg_load_gen(shortfall_data)
    for kk, vv in region_load.items():
        load_gens_simu[kk] = region_load[kk].merge(region_gens[kk],on=region_load[kk].index)
        load_gens_simu[kk] = load_gens_simu[kk].rename(columns={0:"demand"})
        del load_gens_simu[kk]["key_0"]
    return load_gens_simu


def plot_yearly_rlg_v1(load_gens_simu, shortfall_data, 
                       resample='monthly', scenario="MT"):
    figsize = (25,10)
    fig, axes = plt.subplots(figsize=figsize, nrows=3, ncols=5)
    # plt.subplots_adjust(wspace=0, hspace=0)
    if resample == "monthly":
        title = "Average "+resample+" load, generation and storage \nfor each regions in the " + scenario
    elif resample == "yearly":
        title = "Average "+resample+" load, generation and storage \nfor each regions in the " + scenario
    elif resample == "weekly":
        title = "Average "+resample+" load, generation and storage \nfor each regions in 2024-25 in the " + scenario
    fig.suptitle(title, fontweight='bold')
    color_map = {'NATURAL_GAS':'orange', 'ST':'brown','WT':'green',
                 'PVe':'yellow','DISTILLATE_FUEL_OIL':'red', 'Battery':'purple',
                 'COAL':'black','Hydro':'blue','demand':'gray'}
    x = 0
    y = 0
    for i, col in enumerate(load_gens_simu.keys()):
        load_gens_simu[col]['timestamp'] = shortfall_data["timestamps"]
        load_gens_simu[col]['timestamp'] = pd.to_datetime(load_gens_simu[col]['timestamp'])
        load_gens_simu[col] = load_gens_simu[col].set_index('timestamp')
        col_names = load_gens_simu[col].columns.to_list()
        matched_col = [color_map[key] for key in col_names]
        if i == 0:
            axes[x,y].set_ylabel('GW') 
        if i == 5 :
            x = 1
            y = 0
            axes[x,y].set_ylabel('GW') 
        if i == 10 :
            x = 2
            y = 0
            axes[x,y].set_ylabel('GW') 
        if resample == "monthly":
            my_data = load_gens_simu[col].resample('ME').mean()/1000
        elif resample == "yearly":
            my_data = load_gens_simu[col].resample('YE').mean()/1000
        elif resample == "weekly":
            my_data = load_gens_simu[col].resample('W').mean()/1000
        
        if i == 4:
            my_data.plot(legend=True, color=matched_col, linewidth=3, ax=axes[x,y])
            axes[x,y].legend(loc='upper left', bbox_to_anchor=(1, 1),
                            prop={'weight': 'bold'})
        else:
            my_data.plot(legend=False, color=matched_col, linewidth=3, ax=axes[x,y])
        #axes[x,y].set_xlabel("")
        #axes[x,y].set_xticks([]) 
        axes[x,y].grid(True, which='both', linewidth=0.3, color='lightgray')
        axes[x,y].tick_params(axis='x', labelrotation=45)
        for label in axes[x,y].get_xticklabels():
            label.set_fontweight('bold')
        for label in axes[x,y].get_yticklabels():
            label.set_fontweight('bold')
        axes[x,y].set_xlabel('') 
        #if x != 2:
        #    axes[x,y].set_xticks([])
        axes[x,y].set_title(col, y=0.5, va='top', weight="bold")        
        y += 1

def plot_flow(target_region, flow_for, st_date, en_date, scenario, figsize):
    flow_names = [item for item in flow_for.columns if target_region in item]
    for flow_name in flow_names:
        ff = flow_for[(flow_for.index >= st_date) & (flow_for.index < en_date)]
        fig, ax1 = plt.subplots(figsize=figsize, nrows=1, ncols=1)
        ff[flow_name].plot(ax=ax1)
        for label in ax1.get_xticklabels():
            label.set_fontweight('bold')
        for label in ax1.get_yticklabels():
            label.set_fontweight('bold')
        ax1.set_ylabel("MW", fontweight='bold')
        ax1.legend(prop={'weight': 'bold'})
        title = "Load flow in: "+ flow_name + " for scenario: " + scenario
        ax1.set_title(title, weight="bold") 
        ax1.grid()


def plot_EUE_lgs(target_region, st_date, en_date, 
                 shortfall_data, area_code_region,
                 scenario, IDIR, figsize):
    eue_df = load_eue_shortfall(area_code_region, scenario, IDIR)
    fig, ax1 = plt.subplots(figsize=figsize, nrows=1, ncols=1)
    my_data = eue_df[(eue_df.index > st_date) & (eue_df.index < en_date)][target_region]
    my_data = pd.DataFrame(my_data)
    my_data.reset_index().plot.scatter(x='timestamp',y=target_region,
                                   label="EUE", color='r', style="*",
                                   s=50, ax=ax1)
    ax1.set_xlabel("")
    ax1.tick_params(axis='x', labelrotation=45)
    ax1.legend(prop={'weight': 'bold'})
    for label in ax1.get_xticklabels():
        label.set_fontweight('bold')
    for label in ax1.get_yticklabels():
        label.set_fontweight('bold')
    ax1.set_ylabel("MWh/year", fontweight='bold')
    title = "Expected Unserved Energy in "+target_region + " for scenario: " + scenario
    ax1.set_title(title, weight="bold")
    ax1.grid()
    load_gen, gen_cap = get_all_info(target_region, shortfall_data, area_code_region)
    lg = load_gen[(load_gen.index >= st_date) & (load_gen.index < en_date)]
    gc = gen_cap[(gen_cap.index >= st_date) & (gen_cap.index < en_date)]
    my_data = pd.concat([lg, gc])
    fig, ax1 = plt.subplots(figsize=figsize, nrows=1, ncols=1)
    my_data.plot(ax=ax1)
    for label in ax1.get_xticklabels():
        label.set_fontweight('bold')
    for label in ax1.get_yticklabels():
        label.set_fontweight('bold')
    ax1.set_ylabel("MW", fontweight='bold')
    ax1.legend(prop={'weight': 'bold'})
    title = "Load, generation and storage in "+ target_region + " for scenario: " + scenario
    ax1.set_title(title, weight="bold") 
    ax1.grid()
    

def plot_metrics(flow_for, scenario):
    figsize = (25,10)
    fig, axes = plt.subplots(figsize=figsize, nrows=3, ncols=5)
    # plt.subplots_adjust(wspace=0, hspace=0)
    title = "Daily Average flow (MW) for the scenario: " + scenario
    fig.suptitle(title, fontweight='bold')
    flow_for.columns = flow_for.columns.str.replace('_mean_flow', '')
    x = 0
    y = 0
    for i, col in enumerate(flow_for.columns.tolist()):
        if i == 5 :
            x = 1
            y = 0
        if i == 10 :
            x = 2
            y = 0
        flow_for[col].resample('D').mean().plot(legend=True, ax=axes[x,y])
        axes[x,y].tick_params(axis='x', labelrotation=45)
        axes[x,y].set_xlabel('') 
        #if x != 2:
        #    axes[x,y].set_xticks([])
        #else:
        for label in axes[x,y].get_xticklabels():
            label.set_fontweight('bold')    
        axes[x,y].grid() 
        for label in axes[x,y].get_yticklabels():
            label.set_fontweight('bold')
        axes[x,y].legend(prop={'weight': 'bold'})
        y += 1



def util_flow(pras_flow, area_code_region):
    for kk in pras_flow.columns.tolist():
        pras_flow[kk] = pras_flow[kk].apply(ast.literal_eval)
        interface_list = [ast.literal_eval(item) for item in  pras_flow.columns.tolist()]
    interface_names = []
    for i, k in enumerate(interface_list):
        from_reg = area_code_region[k[0]]
        to_reg = area_code_region[k[1]]
        name = from_reg + "-" + to_reg
        interface_names.append(name)
    interface_dict = dict(zip(interface_names,interface_list))
    col_dict = dict(zip(pras_flow.columns.tolist(), interface_names))
    pras_flow = pras_flow.rename(columns = col_dict)
    cols = pras_flow.columns 
    for col in cols:
        new_col = [col + '_mean_flow', col + '_std_flow']
        pras_flow[new_col] = pras_flow[col].apply(pd.Series)
    mean_flow =  pras_flow.filter(regex='_mean_flow') 
    std_flow =  pras_flow.filter(regex='_std_flow') 
    return mean_flow, std_flow

def load_flow_util(area_code_region, flow_file_name):
    
    #pras_util = pd.read_csv("../../../../data/ISP_data/pras_metrics_output/pras_util_timeseries_1.csv")
    #pras_util = pd.read_csv(util_file_name)
    #pras_util['timestamp'] = pd.to_datetime(pras_util['timestamp'], utc=True)
    #pras_util = pras_util.set_index('timestamp')
    #util_for, util_back = util_flow(pras_util, area_code_region)
    #pras_flow = pd.read_csv("../../../../data/ISP_data/pras_metrics_output/pras_flow_timeseries_1.csv")

    pras_flow = pd.read_csv(flow_file_name)
    pras_flow['timestamp'] = pd.to_datetime(pras_flow['timestamp'], utc=True)
    pras_flow = pras_flow.set_index('timestamp')
    mean_flow, std_flow = util_flow(pras_flow, area_code_region)
    #df_flow_filtered = mean_flow.loc[:, (flow_for == 0).all(axis=0)]
    #df_flow_filtered = mean_flow.drop(columns=df_flow_filtered.columns.tolist())
    return mean_flow, std_flow

def load_scenario_data(scenario, IDIR, area_code_region):
    #util_file_name = os.path.join(IDIR, scenario, "pras_util_timeseries.csv")
    flow_file_name = os.path.join(IDIR, scenario, "pras_flow_timeseries.csv")
    mean_flow, std_flow = load_flow_util(area_code_region,  flow_file_name)
    #limit_file = "../data/output/pras_interface_lim_for.csv"
    #for_back_limit = for_back_stats(area_code_region, limit_file)
    #plot_cap(for_back_limit, mean_flow)
    plot_metrics(mean_flow, scenario)
        
    return mean_flow, std_flow    

def plot_mean_values(error_dict):
    lole_std = error_dict["lole_mean"]
    lole_std = error_dict["lole_mean"]
    neue_std = error_dict["neue_mean"]
    eue_std = error_dict["eue_mean"]
    figsize = (15,5)
    fig, axes = plt.subplots(figsize=figsize, nrows=1, ncols=3)
#lole_mean[["Region", "Value"]].set_index("Region").plot(kind="bar",ax=axes)
    lole_std[["Region", "Value"]].set_index("Region").plot(kind="bar",ax=axes[0],color='b')
    eue_std[["Region", "Value"]].set_index("Region").plot(kind="bar",ax=axes[1],color='r')
    neue_std[["Region", "Value"]].set_index("Region").plot(kind="bar",ax=axes[2],color='y')
    axes[0].set_title("LOLE Mean - average shortfall counts \nin event-hours per year (LOLH)")
    axes[1].set_title("EUE Mean - average shortfall in MWH")
    axes[2].set_title("NEUE Mean - normalised \nexpected unserved energy (ppm)")
    axes[0].grid()
    axes[1].grid()
    axes[2].grid()
    plt.subplots_adjust(wspace=0.1, hspace=1)


def plot_std_error(error_dict):
    lole_std = error_dict["lole_std"]
    neue_std = error_dict["neue_std"]
    eue_std = error_dict["eue_std"]
    figsize = (15,5)
    fig, axes = plt.subplots(figsize=figsize, nrows=1, ncols=3)
#lole_mean[["Region", "Value"]].set_index("Region").plot(kind="bar",ax=axes)
    lole_std[["Region", "Value"]].set_index("Region").plot(kind="bar",ax=axes[0],color='b')
    eue_std[["Region", "Value"]].set_index("Region").plot(kind="bar",ax=axes[1],color='r')
    neue_std[["Region", "Value"]].set_index("Region").plot(kind="bar",ax=axes[2],color='y')
    axes[0].set_title("LOLE stderror")
    axes[1].set_title("EUE stderror")
    axes[2].set_title("NEUE stderror")
    axes[0].grid()
    axes[1].grid()
    axes[2].grid()
    plt.subplots_adjust(wspace=0.1, hspace=1)

def get_shortfall_data(data_file, area_code_region):
    with open(data_file, 'r') as f:
        shortfall_data = json.load(f)
    stats_pras = {}
    for i, kk in enumerate(shortfall_data['region_results']):
    #print("index:",i,",", area_code_region[int(kk["name"])], "(" + kk["name"] + ")"  ",", "eue:", kk["eue"], ",lole:",
    #      kk["lole"], ",", "neue:",kk["neue"])
        stats_pras[area_code_region[int(kk["name"])]] = {"eue": kk["eue"], "lole": kk["lole"], "neue":kk["neue"]}
    

    flat_data = {
        (region, pm, metric): value
        for region, pras_mets in stats_pras.items()
        for pm, sts in pras_mets.items()
        for metric, value in sts.items()
    }

# Create a MultiIndex from the flattened keys
    multi_index = pd.MultiIndex.from_tuples(flat_data.keys(), names=['Region', 'Pras_metrics', 'Stats'])

# Create the DataFrame
    df = pd.DataFrame(list(flat_data.values()), index=multi_index, columns=['Value'])
    df = df.reset_index()
#df[df["Value"]<10].plot(kind="bar")
    lole_mean = df[(df.Pras_metrics == "lole")  & (df.Stats == "mean")]
    lole_std = df[(df.Pras_metrics == "lole")  & (df.Stats == "stderror")]
    eue_mean = df[(df.Pras_metrics == "eue")  & (df.Stats == "mean")]
    eue_std = df[(df.Pras_metrics == "eue")  & (df.Stats == "stderror")]
    neue_mean = df[(df.Pras_metrics == "neue")  & (df.Stats == "mean")]
    neue_std = df[(df.Pras_metrics == "neue")  & (df.Stats == "stderror")]
#lole_mean.groupby('Region').plot(kind='bar')
    return lole_mean, lole_std, eue_mean, eue_std, neue_mean, neue_std, shortfall_data

def get_all_info(target_region, shortfall_data, area_code_region):
    found_key = next((key for key, value in area_code_region.items() if value == target_region), None)
    #figsize = (25,10)
    index = -1
    for inx, i in enumerate(shortfall_data["region_results"]):
        if i["name"] == str(found_key):
            index = inx
            break
    #print("index:", index)
    nsa_load = shortfall_data["region_results"][index]["load"]
    timestamp = shortfall_data["timestamps"]
    nsa_load = pd.DataFrame(nsa_load)
    nsa_load.index = timestamp
    nsa_load.index = pd.to_datetime(nsa_load.index, utc=True)
    nsa_gen_cap = shortfall_data["region_results"][index]["capacity"]
   
    nsa_gen_cap = pd.DataFrame(nsa_gen_cap)
    nsa_gen_cap.index = timestamp
    nsa_gen_cap.index = pd.to_datetime(nsa_gen_cap.index, utc=True)
    
    nsa_gen_cap['tot_gen'] = nsa_gen_cap.sum(axis=1)
    nsa_gen_cap = pd.DataFrame(nsa_gen_cap['tot_gen'])
    nsa_load = nsa_load.rename(columns={0:"load"})
    nsa_load_gen = nsa_load.merge(nsa_gen_cap, on=nsa_load.index)
    nsa_load_gen = nsa_load_gen.rename(columns={'key_0': 'timestamp'})
    nsa_load_gen = nsa_load_gen.set_index('timestamp')
    #fig, ax1 = plt.subplots(figsize=figsize, nrows=1, ncols=1)
    nsa_gen_cap = shortfall_data["region_results"][index]["capacity"]
    nsa_gen_cap = pd.DataFrame(nsa_gen_cap)
    nsa_gen_cap.index = timestamp
    nsa_gen_cap.index = pd.to_datetime(nsa_gen_cap.index, utc=True)
    #nsa_load_gen.plot(ax=ax1)
    #nsa_gen_cap.plot(ax=ax1)
    #xx = ax1.set_title("Load, generation and storage for:" + target_region)
    return nsa_load_gen, nsa_gen_cap

def mean_shortfall_period(sd, timestamps, test_case_timestump, area_code_region, eue_df):
    figsize = (20,4)
    
    demand_zones ={'NSW':['CNSW', 'NNSW', 'SNSW', 'SNW'],
              'QLD':['CQ', 'GG', 'NQ', 'SQ'],
               'SA':['NSA', 'CSA', 'SESA'],
               'VIC':['WNV', 'MEL', 'SEV'],
               'TAS':['TAS']}
    def find_key(target_value, my_dict):
        for key, value in my_dict.items():
            if target_value in value:
               return key
 
    region_list = ["NSW","QLD","VIC","SA","TAS"]
    
    for vv in sd:
        sub_region = area_code_region[int(vv["name"])]
        region = find_key(sub_region, demand_zones)
        title = "Shortfall mean for " + sub_region
        title2 = "EUE values with LOLE = 1 instances \n where that hour had a shortfall in every MC sample"  
        if region == region_list[0] and len(vv["shortfall_timestamps"]) > 0:
            
            sf = pd.DataFrame({"timestamp":timestamps, 
              "shortfall_mean":vv["shortfall_mean"]})
            sf = sf.set_index('timestamp')
            fig, (ax1,ax2) = plt.subplots(figsize=figsize, nrows=1, ncols=2)
            sf.plot(ax=ax1, title=title,legend=False)
            eue_df.reset_index().plot.scatter(x='timestamp', y=sub_region, ax=ax2, title=title2, color='r',marker="*")
            plt.tight_layout()
            ax1.grid()
            ax2.grid()
           
            
        elif region == region_list[1] and len(vv["shortfall_timestamps"]) > 0:
            
            sf = pd.DataFrame({"timestamp":timestamps, 
              "shortfall_mean":vv["shortfall_mean"]})
            sf = sf.set_index('timestamp')
            fig, (ax1,ax2) = plt.subplots(figsize=figsize, nrows=1, ncols=2)
            sf.plot(ax=ax1, title=title,legend=False)
            eue_df.reset_index().plot.scatter(x='timestamp', y=sub_region, ax=ax2, title=title2, color='r',marker="*")
            plt.tight_layout()
            ax1.grid()
            ax2.grid()
            
        elif region == region_list[2] and len(vv["shortfall_timestamps"]) > 0:
            
            sf = pd.DataFrame({"timestamp":timestamps, 
              "shortfall_mean":vv["shortfall_mean"]})
            sf = sf.set_index('timestamp')
            fig, (ax1,ax2) = plt.subplots(figsize=figsize, nrows=1, ncols=2)
            sf.plot(ax=ax1, title=title,legend=False)
            eue_df.reset_index().plot.scatter(x='timestamp', y=sub_region, ax=ax2, title=title2, color='r',marker="*")
            plt.tight_layout()
            ax1.grid()
            ax2.grid()
            
            
        elif region == region_list[3] and len(vv["shortfall_timestamps"]) > 0:
            
            sf = pd.DataFrame({"timestamp":timestamps, 
              "shortfall_mean":vv["shortfall_mean"]})
            sf = sf.set_index('timestamp')
            fig, (ax1,ax2) = plt.subplots(figsize=figsize, nrows=1, ncols=2)
            sf.plot(ax=ax1, title=title,legend=False)
            eue_df.reset_index().plot.scatter(x='timestamp', y=sub_region, ax=ax2, title=title2, color='r',marker="*")
            plt.tight_layout()
            ax1.grid()
            ax2.grid()
            
        elif region == region_list[4] and len(vv["shortfall_timestamps"]) > 0:
            
            sf = pd.DataFrame({"timestamp":timestamps, 
              "shortfall_mean":vv["shortfall_mean"]})
            sf = sf.set_index('timestamp')
            fig, (ax1,ax2) = plt.subplots(figsize=figsize, nrows=1, ncols=2)
            sf.plot(ax=ax1, title=title,legend=False)
            eue_df.reset_index().plot.scatter(x='timestamp', y=sub_region, ax=ax2, title=title2, color='r',marker="*")
            plt.tight_layout()
            ax1.grid()
            ax2.grid()

