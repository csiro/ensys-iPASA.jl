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

def flow_result(scenario, area_code_region):
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
 
    figsize = (10,5)
    fig, axes = plt.subplots(figsize=figsize, nrows=3, ncols=5)
    plt.subplots_adjust(wspace=0, hspace=0)
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

def plot_metrics(flow_for):
    figsize = (10,5)
    fig, axes = plt.subplots(figsize=figsize, nrows=3, ncols=5)
    plt.subplots_adjust(wspace=0, hspace=0)
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
        flow_for[col].resample('D').mean().plot(legend=True, ax=axes[x,y])
        #axes[x,y].set_xlabel("")
        #axes[x,y].set_xticks([]) 
        axes[x,y].tick_params(axis='x', labelrotation=45)
        axes[x,y].set_xlabel('') 
        if x != 2:
            axes[x,y].set_xticks([])
            
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

def load_flow_util(area_code_region, util_file_name, flow_file_name):
    
    #pras_util = pd.read_csv("../../../../data/ISP_data/pras_metrics_output/pras_util_timeseries_1.csv")
    pras_util = pd.read_csv(util_file_name)
    pras_util['timestamp'] = pd.to_datetime(pras_util['timestamp'], utc=True)
    pras_util = pras_util.set_index('timestamp')
    util_for, util_back = util_flow(pras_util, area_code_region)
    #pras_flow = pd.read_csv("../../../../data/ISP_data/pras_metrics_output/pras_flow_timeseries_1.csv")

    pras_flow = pd.read_csv(flow_file_name)
    pras_flow['timestamp'] = pd.to_datetime(pras_flow['timestamp'], utc=True)
    pras_flow = pras_flow.set_index('timestamp')
    mean_flow, std_flow = util_flow(pras_flow, area_code_region)
    #df_flow_filtered = mean_flow.loc[:, (flow_for == 0).all(axis=0)]
    #df_flow_filtered = mean_flow.drop(columns=df_flow_filtered.columns.tolist())
    return mean_flow, std_flow

def load_scenario_data(scenario, IDIR, area_code_region):
    util_file_name = os.path.join(IDIR, scenario, "pras_util_timeseries.csv")
    flow_file_name = os.path.join(IDIR, scenario, "pras_flow_timeseries.csv")
    mean_flow, std_flow = load_flow_util(area_code_region, util_file_name, flow_file_name)
    #limit_file = "../data/output/pras_interface_lim_for.csv"
    #for_back_limit = for_back_stats(area_code_region, limit_file)
    #plot_cap(for_back_limit, mean_flow)
    plot_metrics(mean_flow)
        
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
    figsize = (25,10)
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
    fig, ax1 = plt.subplots(figsize=figsize, nrows=1, ncols=1)
    nsa_gen_cap = shortfall_data["region_results"][index]["capacity"]
    nsa_gen_cap = pd.DataFrame(nsa_gen_cap)
    nsa_gen_cap.index = timestamp
    nsa_gen_cap.index = pd.to_datetime(nsa_gen_cap.index, utc=True)
    nsa_load_gen.plot(ax=ax1)
    nsa_gen_cap.plot(ax=ax1)
    xx = ax1.set_title("Load, generation and storage for:" + target_region)

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

